require "../spec_helper"

# The documentation URL this app hands out, which crystaldocs has to be able to
# read back. Both apps spell the key the same way; `CrystalDocs::PackagePaths`
# is the counterpart.
#
# The origin is read from configuration in every assertion below rather than
# written out. Spelling a host here would pass whether or not the value was
# configurable, which is exactly how a hardcoded production URL survived long
# enough to point every development machine's documentation links at
# production.
private def origin : String
  CrystalShards::DocsSite.origin
end

# Runs the block with DOCS_SITE_ORIGIN set to `value`, or absent when nil, and
# puts the environment back afterwards whatever happens.
private def with_origin(value : String?, &)
  key = CrystalShards::DocsSite::ENV_KEY
  previous = ENV[key]?

  if value
    ENV[key] = value
  else
    ENV.delete(key)
  end

  begin
    yield
  ensure
    if previous
      ENV[key] = previous
    else
      ENV.delete(key)
    end
  end
end

describe CrystalShards::DocsSite do
  describe ".origin" do
    it "comes from configuration" do
      with_origin("https://docs.example.test") do
        CrystalShards::DocsSite.origin.should eq("https://docs.example.test")
      end
    end

    # A trailing slash in the variable would otherwise produce a double slash in
    # every link, which resolves but is not the canonical URL.
    it "does not double the separator when the origin has a trailing slash" do
      with_origin("https://docs.example.test/") do
        CrystalShards::DocsSite.url_for("crystal", "1.0.0")
          .should eq("https://docs.example.test/docs/crystal/1.0.0")
      end
    end

    # No default, in any environment. A guess about where another service lives
    # produces links that resolve somewhere real, which is the failure nobody
    # notices; a startup error naming the variable is the one they do.
    it "refuses to guess when it is unset" do
      with_origin(nil) do
        message = expect_raises(CrystalShards::DocsSite::MissingOrigin) do
          CrystalShards::DocsSite.origin
        end.message.to_s

        message.should contain(CrystalShards::DocsSite::ENV_KEY)
      end
    end

    it "refuses a blank value the same way" do
      with_origin("   ") do
        expect_raises(CrystalShards::DocsSite::MissingOrigin) do
          CrystalShards::DocsSite.origin
        end
      end
    end
  end

  describe ".url_for?" do
    it "addresses a shard by its repository" do
      shard = ShardFactory.create &.name("kemal")
        .host("github.com").owner("kemalcr").repo("kemal")
        .canonical_slug("github.com/kemalcr/kemal")

      CrystalShards::DocsSite.url_for?(shard)
        .should eq("#{origin}/docs/_/github.com/kemalcr/kemal")
    end

    # Two shards can be called router, so a name is not something to build a
    # documentation URL from. A row with no identity has no URL at all, and
    # saying so beats pointing at whichever repository claimed the name.
    it "has no URL for a shard with no identity" do
      shard = insert_unidentified_shard("legacy")

      CrystalShards::DocsSite.url_for?(shard).should be_nil
    end

    it "gives two same-named shards two different URLs" do
      github = ShardFactory.create &.name("router")
        .host("github.com").owner("acme").repo("router")
        .canonical_slug("github.com/acme/router")
      gitlab = ShardFactory.create &.name("router")
        .host("gitlab.com").owner("acme").repo("router")
        .canonical_slug("gitlab.com/acme/router")

      CrystalShards::DocsSite.url_for?(github)
        .should_not eq(CrystalShards::DocsSite.url_for?(gitlab))
    end
  end

  # The version form is what a completed build records, and it has to be a URL
  # that resolves. The old one omitted /docs and 404'd.
  describe ".url_for with a version" do
    it "puts a repository key under the repository segment" do
      CrystalShards::DocsSite.url_for("github.com/kemalcr/kemal", "1.6.0")
        .should eq("#{origin}/docs/_/github.com/kemalcr/kemal/1.6.0")
    end

    it "leaves a bare key at the URL that is already indexed" do
      CrystalShards::DocsSite.url_for("crystal", "1.21.0")
        .should eq("#{origin}/docs/crystal/1.21.0")
    end
  end
end
