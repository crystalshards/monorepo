# Recorded response shapes for the hosts discovery crawls.
#
# Provenance is stated per fixture and matters, because a fixture invented from
# a docs page proves only that the parser agrees with the fixture.
#
#   VERIFIED LIVE   fields and headers copied from a real unauthenticated
#                   request made while writing this, trimmed to the fields the
#                   crawler reads plus enough neighbours to keep the shape
#                   recognisable.
#   FROM DOCS       built from GitHub's REST documentation, because the endpoint
#                   answers an unauthenticated request with 401 and no token was
#                   available to record a real one.
#   LIVE SHAPE,     the status line, headers and delivery are copied from a real
#   SYNTHETIC BODY  response and only the file's bytes are invented. Exactly one
#                   fixture is in this category, `bitbucket_shard_yml_response`,
#                   and the reason is worth writing down rather than leaving as
#                   an apology.
#
#                   Bitbucket's raw file endpoint was recorded live returning
#                   200 with `content-type: text/plain` and the file's bytes as
#                   the whole body, from
#                   GET /2.0/repositories/tutorials/markdowndemo/src/master/README.md.
#                   That is the entire transport: there is no envelope, no
#                   encoding and no metadata for a fixture to get wrong, and the
#                   response for a shard.yml differs only in which bytes come
#                   back. What could not be recorded is a real Bitbucket
#                   shard.yml, because there does not appear to be one.
#
#                   Searched, all empty of any Bitbucket-hosted Crystal shard:
#                     - shardbox.org, the Crystal shard registry
#                     - veelenga/awesome-crystal, zero occurrences of "bitbucket"
#                     - GitHub code search, `"bitbucket:" filename:shard.yml`
#                       (3 hits, all resolver documentation and IDE test data)
#                     - GitHub code search, `"bitbucket.org" filename:shard.yml`
#                       and `bitbucket.org filename:shard.lock`
#                     - the 829 shards already in this registry, none on this host
#                     - the 30 most prolific shard authors in that registry,
#                       probed as Bitbucket workspaces with q=language="crystal":
#                       3 readable anonymously, all with zero Crystal repositories,
#                       the rest 403 or 404
#                     - a live sweep of the `tutorials` workspace: 11 repositories,
#                       11 clean 404s, zero shards
#
#                   So this fixture proves the parser, the registration path and
#                   the update-not-duplicate behaviour. It proves nothing about
#                   what a Bitbucket shard.yml looks like, and the 404 fixtures
#                   either side of it, which decide the far more common "this is
#                   not a shard" answer, are both verbatim recordings.
module Discovery::Fixtures
  # FROM DOCS. GET /search/code, which requires authentication: an
  # unauthenticated request returns 401 {"message":"Requires authentication"},
  # verified live. The wrapper (total_count / incomplete_results / items) is the
  # same envelope as /search/repositories, which WAS verified live, and each item
  # carries `path` plus a nested `repository` object.
  def self.github_code_search(items : Array({String, String}), total : Int32) : String
    entries = items.map do |(full_name, description)|
      owner, _, repo = full_name.partition('/')
      <<-JSON
        {
          "name": "shard.yml",
          "path": "shard.yml",
          "sha": "b1946ac92492d2347c6235b4d2611184",
          "url": "https://api.github.com/repositories/1/contents/shard.yml",
          "html_url": "https://github.com/#{full_name}/blob/master/shard.yml",
          "repository": {
            "id": 1,
            "name": "#{repo}",
            "full_name": "#{full_name}",
            "owner": {"login": "#{owner}", "id": 2, "type": "User"},
            "html_url": "https://github.com/#{full_name}",
            "description": #{description.empty? ? "null" : description.to_json},
            "fork": false,
            "default_branch": "master"
          },
          "score": 1.0
        }
        JSON
    end

    <<-JSON
      {
        "total_count": #{total},
        "incomplete_results": false,
        "items": [#{entries.join(",")}]
      }
      JSON
  end

  # VERIFIED LIVE. GET /repos/{owner}/{repo}/contents/shard.yml against
  # kemalcr/kemal returned exactly this shape with 200, and the same path on
  # torvalds/linux returned 404. Content is base64 with newlines, which is why
  # the crawler strips whitespace before decoding.
  def self.github_contents(shard_yml : String) : String
    encoded = Base64.encode(shard_yml) # encode/64 inserts newlines, as GitHub does
    <<-JSON
      {
        "name": "shard.yml",
        "path": "shard.yml",
        "sha": "930216ba8c4c5c5741d34d2d51cb74fc2fb8f549",
        "size": #{shard_yml.bytesize},
        "url": "https://api.github.com/repos/o/r/contents/shard.yml",
        "html_url": "https://github.com/o/r/blob/master/shard.yml",
        "git_url": "https://api.github.com/repos/o/r/git/blobs/930216b",
        "download_url": "https://raw.githubusercontent.com/o/r/master/shard.yml",
        "type": "file",
        "content": #{encoded.to_json},
        "encoding": "base64"
      }
      JSON
  end

  # VERIFIED LIVE. GET /api/v4/projects?topic=crystal returned this item shape,
  # with pagination in the x-next-page / x-total / x-total-pages headers.
  def self.gitlab_projects(projects : Array({String, String})) : String
    entries = projects.map_with_index do |(path_with_namespace, description), index|
      name = path_with_namespace.split('/').last
      <<-JSON
        {
          "id": #{82571311 + index},
          "description": #{description.empty? ? "null" : description.to_json},
          "name": "#{name}",
          "name_with_namespace": "#{path_with_namespace.split('/').join(" / ")}",
          "path": "#{name}",
          "path_with_namespace": "#{path_with_namespace}",
          "created_at": "2026-05-26T17:20:27.978Z",
          "default_branch": "master",
          "ssh_url_to_repo": "git@gitlab.com:#{path_with_namespace}.git",
          "http_url_to_repo": "https://gitlab.com/#{path_with_namespace}.git",
          "web_url": "https://gitlab.com/#{path_with_namespace}",
          "forks_count": 0,
          "star_count": 3,
          "last_activity_at": "2026-08-11T03:39:09.045Z",
          "topics": ["crystal"],
          "visibility": "public"
        }
        JSON
    end

    "[#{entries.join(",")}]"
  end

  # VERIFIED LIVE. GET /api/v1/repos/search?q=crystal&topic=true returned this
  # shape, with the total in x-total-count. Note the parameter spelling: `topic`
  # is a boolean and `q` carries the term. Sending topic=crystal parses as false
  # and returns every repository on the instance, which is how a crawl of
  # Codeberg silently becomes a crawl of 412,000 unrelated repositories.
  def self.codeberg_search(repositories : Array({String, String})) : String
    entries = repositories.map_with_index do |(full_name, description), index|
      owner, _, name = full_name.partition('/')
      <<-JSON
        {
          "id": #{294206 + index},
          "owner": {"id": 250542, "login": "#{owner}", "html_url": "https://codeberg.org/#{owner}"},
          "name": "#{name}",
          "full_name": "#{full_name}",
          "description": #{description.empty? ? "null" : description.to_json},
          "empty": false,
          "private": false,
          "fork": false,
          "mirror": false,
          "size": 64,
          "language": "Crystal",
          "html_url": "https://codeberg.org/#{full_name}",
          "ssh_url": "ssh://git@codeberg.org/#{full_name}.git",
          "clone_url": "https://codeberg.org/#{full_name}.git",
          "website": "",
          "stars_count": 2,
          "forks_count": 0,
          "default_branch": "main",
          "archived": false,
          "topics": ["crystal"]
        }
        JSON
    end

    <<-JSON
      {"ok": true, "data": [#{entries.join(",")}]}
      JSON
  end

  # VERIFIED LIVE. GET /2.0/repositories/tutorials?pagelen=100 returned this
  # envelope and this item shape. The real call reported size 11, page 1 and
  # next absent, and every one of the eleven repositories carried
  # "scm": "git" and "mainbranch": {"name": "master", "type": "branch"}.
  #
  # Two details here are load-bearing rather than decorative.
  #
  # `next` is an ABSOLUTE URL. Live it came back as
  # "https://api.bitbucket.org/2.0/repositories/atlassian?pagelen=2&page=2",
  # and on a workspace addressed by uuid the host substitutes the uuid form.
  # The crawler follows it, because `values` and `next` are the only fields a
  # paginated body guarantees: `page` is optional and `next` may carry an opaque
  # token instead of a number, so a URL rebuilt from a page counter can name a
  # page the host never offered. `page` is nilable here for exactly that reason,
  # so a body can be built in the guaranteed-minimum shape.
  #
  # `language` is "" on seven of the eleven live repositories. That is the
  # measurement behind enumerating a whole workspace instead of filtering on
  # q=language="crystal", which the API does accept.
  def self.bitbucket_repositories(
    repositories : Array({String, String}),
    next_page : String? = nil,
    size : Int32? = nil,
    page : Int32? = 1,
    main_branch : String? = "master",
    scm : String = "git",
  ) : String
    entries = repositories.map do |(full_name, description)|
      workspace, _, slug = full_name.partition('/')
      branch = main_branch ? %({"name": "#{main_branch}", "type": "branch"}) : "null"

      <<-JSON
        {
          "type": "repository",
          "full_name": "#{full_name}",
          "links": {
            "self": {"href": "https://api.bitbucket.org/2.0/repositories/#{full_name}"},
            "html": {"href": "https://bitbucket.org/#{full_name}"},
            "clone": [
              {"name": "https", "href": "https://bitbucket.org/#{full_name}.git"},
              {"name": "ssh", "href": "git@bitbucket.org:#{full_name}.git"}
            ]
          },
          "name": "#{slug}",
          "slug": "#{slug}",
          "description": #{description.to_json},
          "scm": "#{scm}",
          "website": "",
          "owner": {"display_name": "#{workspace}", "type": "team"},
          "workspace": {"slug": "#{workspace}", "name": "#{workspace}", "type": "workspace"},
          "is_private": false,
          "language": "",
          "fork_policy": "allow_forks",
          "created_on": "2011-10-13T23:35:11.622182+00:00",
          "updated_on": "2026-08-11T11:28:45.659483+00:00",
          "size": 2849158,
          "has_issues": true,
          "has_wiki": false,
          "mainbranch": #{branch}
        }
        JSON
    end

    fields = [%("values": [#{entries.join(",")}])]
    fields << %("pagelen": 100)
    fields << %("size": #{size || repositories.size})
    fields << %("page": #{page}) if page
    fields << %("next": #{next_page.to_json}) if next_page

    "{#{fields.join(",")}}"
  end

  # VERIFIED LIVE, verbatim. This is what GET /2.0/repositories answers now, on
  # every variant tried: bare, with pagelen, with after=, and with
  # q=language="crystal". It is the whole reason this host is crawled workspace
  # by workspace, so it is recorded rather than described.
  BITBUCKET_GLOBAL_GONE = <<-JSON
    {"type": "error", "error": {"message": "CHANGE-2770 - Functionality has been deprecated", "detail": "Please read the changelog entry for more details.", "data": {"announcement_url": "https://developer.atlassian.com/cloud/bitbucket/changelog#CHANGE-2770"}}, "data": {"announcement_url": "https://developer.atlassian.com/cloud/bitbucket/changelog#CHANGE-2770"}}
    JSON

  # VERIFIED LIVE, verbatim, with a 404.
  # GET /2.0/repositories/tutorials/markdowndemo/src/master/shard.yml
  BITBUCKET_FILE_MISSING = %({"type":"error","error":{"message":"No such file or directory: shard.yml"}})

  # VERIFIED LIVE, verbatim, with a 404. Same repository, same missing file,
  # different reason: the ref does not exist, because markdowndemo's branch is
  # master and this asked for main.
  # GET /2.0/repositories/tutorials/markdowndemo/src/main/shard.yml
  #
  # The status code is identical to the fixture above. That is why the crawler
  # resolves mainbranch from the enumeration instead of guessing: a guessed
  # branch files a real shard as "not a shard" and nothing in the response
  # distinguishes the two at the level the client reacts to.
  BITBUCKET_REF_MISSING = %({"type":"error","error":{"message":"Commit not found","data":{"shas":["main"]}},"data":{"shas":["main"]}})

  # VERIFIED LIVE headers, verbatim. Bitbucket's rate-limit reset is seconds
  # remaining in the window, not a Unix timestamp: sampled three times it read
  # 745, 737 and 728 while 16.5 seconds of wall clock passed and the clock stood
  # at 1786448872.
  def self.bitbucket_rate_limit_headers(reset_in_seconds : Int32 = 745) : Hash(String, String)
    {
      "x-ratelimit-limit"     => "60, 60;w=3600",
      "x-ratelimit-remaining" => "0",
      "x-ratelimit-reset"     => reset_in_seconds.to_s,
    }
  end

  # LIVE SHAPE, SYNTHETIC BODY. The one fixture in that category; see the header
  # of this file for the search that failed to turn up a real Bitbucket
  # shard.yml and for why the transport around these bytes is nonetheless
  # exactly what the host sends.
  #
  # Recorded from GET /2.0/repositories/tutorials/markdowndemo/src/master/README.md:
  #   HTTP/2 200
  #   content-type: text/plain
  #   <the file's bytes, and nothing else>
  def self.bitbucket_shard_yml_response(name : String, description : String = "A Crystal shard") : {String, Hash(String, String)}
    {shard_yml(name, description), {"Content-Type" => "text/plain"}}
  end

  # A minimal but real shard.yml, the same shape kemal's is.
  def self.shard_yml(name : String, description : String = "A Crystal shard") : String
    <<-YAML
      name: #{name}
      version: 1.2.0
      description: #{description}

      authors:
        - Someone <someone@example.test>

      crystal: ">= 1.0.0"
      license: MIT
      YAML
  end
end
