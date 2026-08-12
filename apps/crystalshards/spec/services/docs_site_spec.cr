require "../spec_helper"

# The documentation URL this app hands out, which crystaldocs has to be able to
# read back. Both apps spell the key the same way; `CrystalDocs::PackagePaths`
# is the counterpart.
describe CrystalShards::DocsSite do
  describe ".url_for?" do
    it "addresses a shard by its repository" do
      shard = ShardFactory.create &.name("kemal")
        .host("github.com").owner("kemalcr").repo("kemal")
        .canonical_slug("github.com/kemalcr/kemal")

      CrystalShards::DocsSite.url_for?(shard)
        .should eq("https://crystaldocs.org/docs/_/github.com/kemalcr/kemal")
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
        .should eq("https://crystaldocs.org/docs/_/github.com/kemalcr/kemal/1.6.0")
    end

    it "leaves a bare key at the URL that is already indexed" do
      CrystalShards::DocsSite.url_for("crystal", "1.21.0")
        .should eq("https://crystaldocs.org/docs/crystal/1.21.0")
    end
  end
end
