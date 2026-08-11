require "../spec_helper"

describe ShardIdentity do
  describe ".parse_url" do
    it "parses the URL shapes the registry stores" do
      cases = {
        "https://github.com/kemalcr/kemal"        => "github.com/kemalcr/kemal",
        "http://github.com/kemalcr/kemal"         => "github.com/kemalcr/kemal",
        "https://github.com/kemalcr/kemal.git"    => "github.com/kemalcr/kemal",
        "https://github.com/kemalcr/kemal/"       => "github.com/kemalcr/kemal",
        "https://gitlab.com/acme/router"          => "gitlab.com/acme/router",
        "https://bitbucket.org/team/lib"          => "bitbucket.org/team/lib",
        "https://codeberg.org/person/thing"       => "codeberg.org/person/thing",
        "https://git.example.co.uk/team/thing"    => "git.example.co.uk/team/thing",
        "git@github.com:kemalcr/kemal.git"        => "github.com/kemalcr/kemal",
        "https://github.com/imdrasil/jennifer.cr" => "github.com/imdrasil/jennifer.cr",
      }

      cases.each do |url, expected|
        ShardIdentity.parse_url(url).try(&.canonical_slug).should eq(expected)
      end
    end

    it "keeps the parts separate rather than only the slug" do
      identity = ShardIdentity.parse_url("https://gitlab.com/acme/router").not_nil!

      identity.host.should eq("gitlab.com")
      identity.owner.should eq("acme")
      identity.repo.should eq("router")
      identity.url_path.should eq("/shards/gitlab.com/acme/router")
    end

    it "downcases the host but leaves owner and repo as the host spells them" do
      identity = ShardIdentity.parse_url("https://GitHub.com/KemalCr/Kemal").not_nil!

      identity.host.should eq("github.com")
      identity.owner.should eq("KemalCr")
      identity.repo.should eq("Kemal")
    end

    it "ignores a query string or fragment" do
      ShardIdentity.parse_url("https://github.com/kemalcr/kemal?tab=readme")
        .try(&.canonical_slug).should eq("github.com/kemalcr/kemal")
      ShardIdentity.parse_url("https://github.com/kemalcr/kemal#install")
        .try(&.canonical_slug).should eq("github.com/kemalcr/kemal")
    end

    # These are the URLs the backfill reports instead of guessing at. Each one
    # would otherwise become a row that cannot be reached by URL or fetched by
    # the indexer.
    it "refuses a URL that does not name one repository on one host" do
      [
        "",
        "   ",
        "https://github.com",
        "https://github.com/",
        "https://github.com/kemalcr",
        "not a url at all",
        "ftp://github.com/owner/repo",
        "https://localhost/owner/repo",
        "https://github.com:8080/owner/repo",
        "https://gitlab.com/group/subgroup/project",
        "https://github.com/owner/repo/tree/master",
        "https://github.com/own er/repo",
        "https://github.com/owner/rep'o",
      ].each do |url|
        ShardIdentity.parse_url(url).should be_nil
      end
    end

    it "treats a nil URL as unparseable rather than raising" do
      ShardIdentity.parse_url(nil).should be_nil
    end
  end

  # The boundary is stated, not incidental: a nested namespace is an ordinary
  # repository we cannot address, and it says so, separately from a URL that is
  # simply not a repository.
  describe ".analyze" do
    it "names a nested namespace path as the reason" do
      result = ShardIdentity.analyze("https://gitlab.com/group/subgroup/project")

      result.should be_a(ShardIdentity::Rejection)
      result.as(ShardIdentity::Rejection).reason.should eq(ShardIdentity::NESTED_NAMESPACE)
    end

    it "names a deeper nested path the same way" do
      result = ShardIdentity.analyze("git@gitlab.com:group/sub/deeper/project.git")

      result.as(ShardIdentity::Rejection).reason.should eq(ShardIdentity::NESTED_NAMESPACE)
    end

    it "distinguishes a URL that names no repository at all" do
      ShardIdentity.analyze("https://github.com/owner")
        .as(ShardIdentity::Rejection).reason.should eq(ShardIdentity::NOT_A_REPO_URL)
      ShardIdentity.analyze("not a url")
        .as(ShardIdentity::Rejection).reason.should eq(ShardIdentity::NOT_A_REPO_URL)
    end

    it "distinguishes a host it cannot use" do
      ShardIdentity.analyze("https://localhost/owner/repo")
        .as(ShardIdentity::Rejection).reason.should eq(ShardIdentity::UNUSABLE_HOST)
    end

    it "distinguishes a name it cannot put in a URL" do
      ShardIdentity.analyze("https://github.com/owner/rep'o")
        .as(ShardIdentity::Rejection).reason.should eq(ShardIdentity::UNUSABLE_SEGMENT)
    end

    it "returns the identity for a supported shape" do
      ShardIdentity.analyze("https://github.com/kemalcr/kemal")
        .as(ShardIdentity::Identity).canonical_slug.should eq("github.com/kemalcr/kemal")
    end
  end

  describe "SaveShard rejection" do
    it "refuses a nested namespace URL with the same reason the row would carry" do
      SaveShard.create(
        name: "project",
        repository_url: "https://gitlab.com/group/subgroup/project",
        provider: "gitlab",
        repository_type: "git"
      ) do |operation, shard|
        shard.should be_nil
        operation.repository_url.errors.should contain(ShardIdentity::NESTED_NAMESPACE)
      end
    end

    it "clears a recorded reason once the URL names a repository" do
      shard = ShardFactory.create &.name("fixed")
        .repository_url("https://github.com/someone/fixed")

      SaveShard.update!(shard, identity_error: "stale reason")
      updated = SaveShard.update!(
        ShardQuery.new.id(shard.id).first,
        repository_url: "https://github.com/someone/fixed-again"
      )

      updated.canonical_slug.should eq("github.com/someone/fixed-again")
      updated.identity_error.should be_nil
    end
  end

  describe ".build" do
    it "builds an identity from parts a crawler already has" do
      ShardIdentity.build("GitLab.com", "acme", "router.git")
        .try(&.canonical_slug).should eq("gitlab.com/acme/router")
    end

    it "refuses parts that could not appear in one of our URLs" do
      ShardIdentity.build("gitlab.com", "group/subgroup", "project").should be_nil
      ShardIdentity.build("localhost", "owner", "repo").should be_nil
      ShardIdentity.build("gitlab.com", "", "repo").should be_nil
    end
  end

  describe ".provider_for" do
    it "maps known hosts to their provider and everything else to git" do
      ShardIdentity.provider_for("github.com").should eq("github")
      ShardIdentity.provider_for("gitlab.com").should eq("gitlab")
      ShardIdentity.provider_for("bitbucket.org").should eq("bitbucket")
      ShardIdentity.provider_for("codeberg.org").should eq("codeberg")
      ShardIdentity.provider_for("git.example.com").should eq("git")
    end
  end

  describe ".upsert" do
    it "creates a shard keyed on its repository" do
      shard = ShardIdentity.upsert(
        host: "gitlab.com",
        owner: "acme",
        repo: "router",
        repository_url: "https://gitlab.com/acme/router",
        name: "router",
        description: "Acme's router"
      )

      shard.canonical_slug.should eq("gitlab.com/acme/router")
      shard.provider.should eq("gitlab")
      shard.description.should eq("Acme's router")
    end

    it "updates the existing row on a second sweep instead of duplicating it" do
      first = ShardIdentity.upsert(
        host: "gitlab.com", owner: "acme", repo: "router",
        repository_url: "https://gitlab.com/acme/router",
        name: "router", description: "First pass"
      )

      second = ShardIdentity.upsert(
        host: "gitlab.com", owner: "acme", repo: "router",
        repository_url: "https://gitlab.com/acme/router",
        name: "router", description: "Second pass"
      )

      second.id.should eq(first.id)
      second.description.should eq("Second pass")
      ShardQuery.new.canonical_slug("gitlab.com/acme/router").select_count.should eq(1)
    end

    it "leaves a stored description alone when a sweep cannot see one" do
      ShardIdentity.upsert(
        host: "gitlab.com", owner: "acme", repo: "router",
        repository_url: "https://gitlab.com/acme/router",
        name: "router", description: "Worth keeping"
      )

      again = ShardIdentity.upsert(
        host: "gitlab.com", owner: "acme", repo: "router",
        repository_url: "https://gitlab.com/acme/router",
        name: "router"
      )

      again.description.should eq("Worth keeping")
    end

    it "refuses an identity the registry could not address" do
      expect_raises(ShardIdentity::InvalidIdentityError) do
        ShardIdentity.upsert(
          host: "gitlab.com", owner: "group/subgroup", repo: "project",
          repository_url: "https://gitlab.com/group/subgroup/project",
          name: "project"
        )
      end
    end
  end

  describe ".mark_unavailable" do
    it "marks a repository the crawler can no longer see, keeping the row" do
      ShardIdentity.upsert(
        host: "codeberg.org", owner: "person", repo: "gone",
        repository_url: "https://codeberg.org/person/gone",
        name: "gone"
      )

      marked = ShardIdentity.mark_unavailable(
        host: "codeberg.org", owner: "person", repo: "gone",
        reason: "404 from host"
      ).not_nil!

      marked.unavailable?.should be_true
      ShardQuery.new.canonical_slug("codeberg.org/person/gone").select_count.should eq(1)
    end

    it "keeps the first time it went missing rather than resetting it" do
      ShardIdentity.upsert(
        host: "codeberg.org", owner: "person", repo: "gone",
        repository_url: "https://codeberg.org/person/gone",
        name: "gone"
      )

      first = ShardIdentity.mark_unavailable(host: "codeberg.org", owner: "person", repo: "gone")
        .not_nil!.unavailable_at
      second = ShardIdentity.mark_unavailable(host: "codeberg.org", owner: "person", repo: "gone")
        .not_nil!.unavailable_at

      second.should eq(first)
    end

    it "clears the marker when the repository comes back" do
      ShardIdentity.upsert(
        host: "codeberg.org", owner: "person", repo: "gone",
        repository_url: "https://codeberg.org/person/gone",
        name: "gone"
      )
      ShardIdentity.mark_unavailable(host: "codeberg.org", owner: "person", repo: "gone")

      back = ShardIdentity.upsert(
        host: "codeberg.org", owner: "person", repo: "gone",
        repository_url: "https://codeberg.org/person/gone",
        name: "gone"
      )

      back.unavailable?.should be_false
    end

    it "reports nothing to mark for an identity we do not have" do
      ShardIdentity.mark_unavailable(host: "github.com", owner: "nobody", repo: "nothing")
        .should be_nil
    end
  end
end
