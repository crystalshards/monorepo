require "../spec_helper"
require "../../src/providers/host_repository_sources"

# Status handling in HostRepositorySource, across Codeberg, GitLab and
# Bitbucket.
#
# GithubRepositoryApi maps a 3xx to NotFound and says why. These three did not:
# anything other than 200, 404, 401 or 403 fell through to Error, so a renamed
# repository was retried on every pass forever and rendered as a fault.
# Measured on codeberg.org/w0u7/email_octopus, which answers 301.
#
# Driven through the injected Requester seam, so the real source classes run
# end to end with nothing on a port.

private def fake_response(status : Int32, body : String = %({"message":"redirect"})) : HostRepositorySource::Requester
  ->(_url : String, _headers : HTTP::Headers) do
    HostRepositorySource::Response.new(status: status, body: body)
  end
end

describe HostRepositorySource do
  describe CodebergRepositorySource do
    it "raises RepositorySource::NotFound when repository answers HTTP 301" do
      source = CodebergRepositorySource.new(
        "w0u7/email_octopus",
        requester: fake_response(301)
      )

      expect_raises(RepositorySource::NotFound, "w0u7/email_octopus has moved: that owner and name no longer address a repository on Codeberg") do
        source.fetch_snapshot
      end
    end

    it "raises RepositorySource::NotFound for other redirect statuses (302, 307, 308)" do
      [302, 307, 308].each do |status|
        source = CodebergRepositorySource.new(
          "w0u7/email_octopus",
          requester: fake_response(status)
        )

        expect_raises(RepositorySource::NotFound, /has moved/) do
          source.fetch_snapshot
        end
      end
    end
  end

  describe GitlabRepositorySource do
    it "raises RepositorySource::NotFound when repository answers HTTP 301" do
      source = GitlabRepositorySource.new(
        "group/project",
        requester: fake_response(301)
      )

      expect_raises(RepositorySource::NotFound, "group/project has moved: that owner and name no longer address a repository on GitLab") do
        source.fetch_snapshot
      end
    end
  end

  describe BitbucketRepositorySource do
    it "raises RepositorySource::NotFound when repository answers HTTP 301" do
      source = BitbucketRepositorySource.new(
        "workspace/repo",
        requester: fake_response(301)
      )

      expect_raises(RepositorySource::NotFound, "workspace/repo has moved: that owner and name no longer address a repository on Bitbucket") do
        source.fetch_snapshot
      end
    end
  end

  describe "other status codes" do
    it "raises RepositorySource::NotFound when repository answers HTTP 404" do
      source = CodebergRepositorySource.new(
        "owner/absent",
        requester: fake_response(404, %({"message":"not found"}))
      )

      expect_raises(RepositorySource::NotFound, "owner/absent is not a repository this credential can see") do
        source.fetch_snapshot
      end
    end

    it "raises RepositorySource::Error when repository answers HTTP 401 or 403" do
      source = CodebergRepositorySource.new(
        "owner/private",
        requester: fake_response(403, %({"message":"forbidden"}))
      )

      expect_raises(RepositorySource::Error, "owner/private was refused: HTTP 403") do
        source.fetch_snapshot
      end
    end

    it "raises RepositorySource::Error when repository answers HTTP 500" do
      source = CodebergRepositorySource.new(
        "owner/broken",
        requester: fake_response(500, %({"message":"internal server error"}))
      )

      expect_raises(RepositorySource::Error, "owner/broken answered HTTP 500") do
        source.fetch_snapshot
      end
    end
  end
end
