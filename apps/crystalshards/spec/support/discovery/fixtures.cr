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
