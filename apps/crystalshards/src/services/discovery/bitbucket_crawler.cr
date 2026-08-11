require "json"
require "base64"
require "./base_crawler"
require "./api_endpoint_policy"

module Discovery
  # Finds shards on Bitbucket by enumerating the workspaces the registry has
  # been told about, and checking each repository for a shard.yml at its root.
  #
  # Why workspaces, and not the whole host. Bitbucket used to answer
  # `GET /2.0/repositories` with every public repository, ordered by creation
  # date. It does not any more. Probed while writing this, unauthenticated:
  #
  #   GET /2.0/repositories                -> 410 Gone
  #   GET /2.0/repositories?pagelen=2      -> 410 Gone
  #   GET /2.0/repositories?after=...      -> 410 Gone
  #   GET /2.0/repositories?q=language=".."-> 410 Gone
  #     {"type": "error", "error": {"message": "CHANGE-2770 - Functionality has
  #      been deprecated", ...}}
  #
  # It is not a parameter problem and it is not an authentication problem: the
  # endpoint is withdrawn, and its sibling firehose `GET /2.0/snippets` returns
  # the same 410 and the same CHANGE-2770. The other doors are shut too.
  # `GET /2.0/workspaces` answers 401, and even authenticated it lists only
  # workspaces the caller already belongs to. `GET /2.0/teams` is gone, 404.
  # The legacy directory at bitbucket.org/repo/all answers 401. Code search
  # exists and works unauthenticated, but its path is
  # `/2.0/workspaces/{workspace}/search/code`: it cannot be asked a question
  # that is not already scoped to a workspace you have named.
  #
  # So there is no query that reaches a stranger's repository on this host, and
  # no crawler can be written that finds one. This is the ATS pattern: the
  # platform cannot be enumerated, so the owner says where to look. Coverage of
  # bitbucket.org is the set of registered workspaces, which is why a finished
  # sweep is recorded as `completed_workspace_scoped` and never as complete.
  #
  # Within a workspace the enumeration is total, and deliberately so. The API
  # accepts `q=language="crystal"`, which would cut the per-repository checks
  # down sharply, and it is not used: of the eleven repositories in the
  # `tutorials` workspace, seven carry `"language": ""`. Filtering on a field
  # the host often leaves blank would silently skip a registered owner's shard,
  # which is the one thing a registration is supposed to prevent.
  class BitbucketCrawler < BaseCrawler
    HOST = "bitbucket.org"
    # The API lives on a different hostname than the repositories. This is the
    # allowlist for the crawler's own requests, and is not, and must not become,
    # the repository allowlist in GitHostPolicy.
    API_HOSTS = ["api.bitbucket.org"]
    PAGE_LEN  = 100

    # Where a sweep is: which workspace, and how far into it.
    #
    # `follow` is the host's own `next` URL for the page after this one. Only
    # `values` and `next` are guaranteed to be in a Bitbucket paginated body:
    # `page` is optional, and `next` is free to carry an opaque token instead of
    # a page number. So the next request has to be the URL the host handed back,
    # not one reconstructed from a page counter, or a sweep silently skips
    # whatever the counter fails to name. `page` is still tracked, but only to
    # count pages against `max_pages`; it never builds a URL after the first.
    #
    # Serialised as JSON because a followed URL contains colons and slashes and
    # cannot be split out of a delimited string safely. Cursors written before
    # this shape existed are still read: see `parse`.
    record Position, slug : String, page : Int32, follow : String? = nil do
      def to_cursor : String
        {slug: slug, page: page, follow: follow}.to_json
      end

      def self.parse(cursor : String) : Position?
        parse_json(cursor) || parse_legacy(cursor)
      end

      # The "<slug>:<page>" form this crawler first shipped with. A cursor in
      # that shape is mid-sweep in a database somewhere, and refusing it would
      # restart those workspaces from the top.
      private def self.parse_legacy(cursor : String) : Position?
        slug, separator, page = cursor.rpartition(':')
        return nil if separator.empty? || slug.empty?

        number = page.to_i?
        return nil unless number && number >= 1

        Position.new(slug, number)
      end

      private def self.parse_json(cursor : String) : Position?
        json = JSON.parse(cursor)
        slug = json["slug"]?.try(&.as_s?).presence
        page = json["page"]?.try(&.as_i?)
        return nil unless slug && page && page >= 1

        Position.new(slug, page, json["follow"]?.try(&.as_s?).presence)
      rescue JSON::ParseException
        nil
      end
    end

    getter workspaces : Array(String)

    # Reported to the caller so a workspace that refused or vanished is recorded
    # against the workspace rather than lost in the host's error column.
    property on_workspace_problem : Proc(String, String, Nil) = ->(_slug : String, _reason : String) { }
    property on_workspace_seen : Proc(String, Int32, Nil) = ->(_slug : String, _count : Int32) { }

    def initialize(
      workspaces : Array(String) = [] of String,
      base_url : String? = nil,
      token : String? = nil,
      username : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      max_pages : Int32? = nil,
    )
      # Sorted and de-duplicated here rather than trusted from the caller. The
      # cursor names a slug and resuming means finding its place in this list
      # again, so the order has to be the same on every run or a resumed sweep
      # picks up in a different workspace than the one it stopped in.
      @workspaces = workspaces.map(&.strip.downcase).reject(&.empty?).uniq.sort!
      @username = username || Credentials.username_for?(HOST)
      super(host: HOST, base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)
    end

    def default_base_url : String
      "https://api.bitbucket.org/2.0"
    end

    # Every request this crawler makes is checked against the endpoint it was
    # configured with, before it is sent. Bitbucket pages with an absolute
    # `next` URL in the response body, so without this the host's own JSON would
    # be able to point the crawl at any address the process can reach.
    def url_gate_for(base_url : String) : Proc(String, Nil)?
      policy = ApiEndpointPolicy.new(base_url, API_HOSTS)
      ->(url : String) { policy.validate!(url) }
    end

    def auth_headers(token : String?) : HTTP::Headers
      headers = HTTP::Headers{"Accept" => "application/json"}

      # Basic, because an app password is half of a pair. Sending the password
      # as a bearer token authenticates as nobody and gets the anonymous 60 an
      # hour, which looks like a working crawl right up until it does not.
      if token && (account = @username)
        headers["Authorization"] = "Basic #{Base64.strict_encode("#{account}:#{token}")}"
      end

      headers
    end

    # Never. There is no enumeration of this host to be exhaustive over, so a
    # finished sweep has seen the registered workspaces and nothing else.
    def exhaustive? : Bool
      false
    end

    def coverage_reason : String
      return CrawlState::StopReason::NO_WORKSPACES_REGISTERED if workspaces.empty?

      CrawlState::StopReason::COMPLETED_WORKSPACE_SCOPED
    end

    def fetch_page(cursor : String?) : CrawlPage
      position = resolve(cursor)
      # No workspaces left, or none registered. Either way the enumeration is
      # over, and coverage_reason is what distinguishes the two.
      return CrawlPage.new([] of DiscoveredRepository, nil) unless position

      payload = begin
        client.get_json(position.follow || page_path(position))
      rescue ex : HostClient::NotFound
        # The workspace does not exist. That will not change by asking again.
        return skip_workspace(position, "no workspace with this id on #{HOST}")
      rescue ex : HostClient::Refused
        # 403 is this workspace saying no to this credential. Stopping here
        # would mean every workspace after it in the list is never reached, on
        # this run or any other, because the cursor would never get past it. So
        # it is counted, recorded against the workspace row, and stepped over.
        # It is retried on the next pass, when the cursor comes back around to
        # the top of the list.
        #
        # Anything else refused is not about this workspace. A 401 is the
        # credential being wrong for the whole host, and skipping all of them
        # one at a time would turn one fixable problem into a list of
        # workspaces that each look individually broken.
        raise ex unless ex.status_code == 403

        return skip_workspace(position, ex.message || "refused")
      end

      values = payload["values"]?.try(&.as_a?) || [] of JSON::Any
      repositories = values.compact_map { |repository| to_repository(repository) }

      on_workspace_seen.call(position.slug, payload["size"]?.try(&.as_i?) || values.size)

      # `next` is the host saying there is another page, and its value is the
      # only thing that reliably names that page. A Bitbucket body is only
      # guaranteed to carry `values` and `next`; `page` may be absent entirely,
      # and `next` may hold an opaque token rather than a page number, so
      # rebuilding the URL from a counter can silently skip a page or re-read
      # one forever. It is followed.
      #
      # Following a URL out of a response body is exactly the thing that needs a
      # gate, so it gets two. `follow_url` pins it to the configured origin and
      # to this workspace's own collection before it is written to the cursor,
      # so a poisoned URL is never persisted, and `url_gate_for` checks it again
      # at request time. A `next` that fails either is a broken page rather than
      # a reason to trust it: the workspace is recorded and stepped over, not
      # quietly truncated to the pages seen so far.
      more = payload["next"]?.try(&.as_s?).presence

      next_cursor = if more
                      following = follow_url(position, more)
                      return skip_workspace(position, "unusable next link: #{more.inspect}") unless following

                      Position.new(position.slug, position.page + 1, following).to_cursor
                    else
                      advance_workspace(position).try(&.to_cursor)
                    end

      CrawlPage.new(repositories, next_cursor)
    end

    def fetch_shard_yml(repository : DiscoveredRepository) : String?
      ref = repository.default_branch
      # Bitbucket's raw file endpoint requires a ref and will not take "the
      # default". A repository with no main branch has no commits, so there is
      # no shard.yml to find and no request worth spending.
      return nil unless ref

      return nil unless BitbucketWorkspace.valid_slug?(repository.owner)
      return nil unless valid_repo_slug?(repository.repo)

      path = "/repositories/#{repository.owner}/#{repository.repo}" \
             "/src/#{URI.encode_path_segment(ref)}/shard.yml"

      client.get(path)
    rescue HostClient::NotFound
      nil
    end

    private def resolve(cursor : String?) : Position?
      return nil if workspaces.empty?

      unless cursor
        first = workspaces.first
        return Position.new(first, 1)
      end

      position = Position.parse(cursor)
      # A cursor that does not parse is not a reason to silently start over and
      # crawl the whole host again, but it is also not resumable. Beginning is
      # the safe answer: identity dedupes the repeats.
      return Position.new(workspaces.first, 1) unless position

      return position if workspaces.includes?(position.slug)

      # The workspace the cursor named is gone from the list, unregistered or
      # disabled between runs. Resume at the next one that would have followed
      # it, so the workspaces after it are not skipped and the ones before it
      # are not redone.
      following = workspaces.find { |slug| slug > position.slug }
      following ? Position.new(following, 1) : nil
    end

    private def advance_workspace(position : Position) : Position?
      following = workspaces.find { |slug| slug > position.slug }
      following ? Position.new(following, 1) : nil
    end

    private def skip_workspace(position : Position, reason : String) : CrawlPage
      report.failed += 1
      message = "#{HOST}/#{position.slug}: #{reason}"
      Log.warn { "Skipping workspace #{message}" }
      on_workspace_problem.call(position.slug, reason)

      CrawlPage.new([] of DiscoveredRepository, advance_workspace(position).try(&.to_cursor))
    end

    # Decides whether the host's `next` URL is one this crawl is willing to
    # follow, and returns it when it is.
    #
    # Two properties, both checked before the URL reaches the cursor, because a
    # cursor is persisted and would otherwise carry a bad destination into every
    # later run:
    #
    #   the origin is the API this crawler was configured with, so the response
    #   cannot move the crawl to another host, and
    #
    #   the path still addresses this workspace's own repository collection, so
    #   a workspace cannot hand the sweep off to a different resource and have
    #   whatever comes back recorded under its own coverage.
    #
    # The query string is deliberately not inspected past that. Its contents are
    # the host's pagination mechanism, page number or opaque token alike, and
    # having an opinion about it is what this change exists to stop doing.
    private def follow_url(position : Position, url : String) : String?
      uri = URI.parse(url)
      return nil unless uri.scheme == configured_uri.scheme
      return nil unless uri.host == configured_uri.host
      return nil unless uri.port == configured_uri.port
      return nil if uri.user || uri.password

      collection = "#{configured_uri.path.rstrip('/')}/repositories/#{position.slug}"
      return nil unless uri.path.rstrip('/') == collection

      url
    rescue URI::Error
      nil
    end

    private getter configured_uri : URI { URI.parse(client.base_url) }

    private def page_path(position : Position) : String
      # Refuse to interpolate a slug that could leave the path it is going into.
      # The registration operation validates this too; a check that only runs on
      # the write path is not a guarantee about the read path.
      unless BitbucketWorkspace.valid_slug?(position.slug)
        raise HostClient::Error.new("#{position.slug.inspect} is not a usable Bitbucket workspace id")
      end

      params = URI::Params.encode({
        "pagelen" => PAGE_LEN.to_s,
        "page"    => position.page.to_s,
        "sort"    => "created_on",
      })

      "/repositories/#{position.slug}?#{params}"
    end

    private def to_repository(repository : JSON::Any) : DiscoveredRepository?
      full_name = repository["full_name"]?.try(&.as_s?)
      return nil unless full_name

      owner, _, name = full_name.partition('/')
      return nil if owner.empty? || name.empty?

      # Bitbucket has no nesting: a full_name is exactly workspace/repo. Anything
      # else is a shape this crawler does not understand, and guessing at it
      # would produce a row whose URL leads nowhere.
      if name.includes?('/')
        report.skipped += 1
        Log.info { "#{HOST}: skipping #{full_name}: #{ShardIdentity::NESTED_NAMESPACE}" }
        return nil
      end

      return nil unless BitbucketWorkspace.valid_slug?(owner) && valid_repo_slug?(name)

      # Mercurial repositories predate Bitbucket dropping hg. Whatever is left of
      # them cannot be cloned by a git provider, so they are not candidates.
      scm = repository["scm"]?.try(&.as_s?)
      if scm && scm != "git"
        report.skipped += 1
        Log.info { "#{HOST}: skipping #{full_name}: #{scm} is not a protocol the registry indexes" }
        return nil
      end

      DiscoveredRepository.new(
        host: HOST,
        owner: owner,
        repo: name,
        # Built here rather than read from links.html.href. The canonical
        # identity is host/owner/repo, so the URL that identifies the row is
        # derived from it and cannot disagree with it.
        repository_url: "https://#{HOST}/#{owner}/#{name}",
        description: repository["description"]?.try(&.as_s?).presence,
        homepage_url: repository["website"]?.try(&.as_s?).presence,
        # The one field that must not be guessed. Asking for src/main on a
        # repository whose branch is master returns 404 "Commit not found",
        # which is the same status as a missing file: guessing the branch files
        # a real shard as "not a shard".
        #
        # A repository with no commits carries "mainbranch": null, and a JSON
        # null is a present value rather than an absent key, so it has to be
        # narrowed to a mapping before it is indexed into.
        default_branch: repository["mainbranch"]?.try(&.as_h?).try(&.["name"]?).try(&.as_s?).presence,
      )
    end

    private def valid_repo_slug?(slug : String) : Bool
      !slug.empty? && slug.size <= 128 && slug.matches?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/) && !slug.includes?("..")
    end
  end
end
