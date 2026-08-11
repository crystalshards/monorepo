require "../spec_helper"

describe ShardQuery do
  describe "#resolve" do
    it "matches a canonical slug exactly" do
      shard = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")

      ShardQuery.new.resolve("github.com/kemalcr/kemal").not_nil!.id.should eq(shard.id)
    end

    it "accepts a bare name while it names exactly one shard" do
      shard = ShardFactory.create &.name("lonely")
        .repository_url("https://github.com/someone/lonely")

      ShardQuery.new.resolve("lonely").not_nil!.id.should eq(shard.id)
    end

    # The whole point: with two candidates there is no right answer, so it
    # refuses instead of returning whichever row came back first.
    it "refuses a bare name that names two shards" do
      ShardFactory.create &.name("router").repository_url("https://github.com/kemalcr/router")
      ShardFactory.create &.name("router").repository_url("https://gitlab.com/acme/router")

      ShardQuery.new.resolve("router").should be_nil
      ShardQuery.new.ambiguous_name?("router").should be_true
    end

    it "still resolves each of the two by identity" do
      github = ShardFactory.create &.name("router")
        .repository_url("https://github.com/kemalcr/router")
      gitlab = ShardFactory.create &.name("router")
        .repository_url("https://gitlab.com/acme/router")

      ShardQuery.new.resolve("github.com/kemalcr/router").not_nil!.id.should eq(github.id)
      ShardQuery.new.resolve("gitlab.com/acme/router").not_nil!.id.should eq(gitlab.id)
    end

    it "prefers a slug match over a name match" do
      # A shard perversely named after another shard's slug must not win the
      # slug lookup.
      named_like_a_slug = ShardFactory.create &.name("github.com/kemalcr/kemal")
        .repository_url("https://github.com/impostor/kemal")
      real = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")

      resolved = ShardQuery.new.resolve("github.com/kemalcr/kemal").not_nil!

      resolved.id.should eq(real.id)
      resolved.id.should_not eq(named_like_a_slug.id)
    end

    it "returns nil for an unknown slug and for an empty key" do
      ShardQuery.new.resolve("github.com/nobody/nothing").should be_nil
      ShardQuery.new.resolve("").should be_nil
    end
  end

  describe "#search" do
    it "finds every shard sharing a name" do
      github = ShardFactory.create &.name("router")
        .repository_url("https://github.com/kemalcr/router")
      gitlab = ShardFactory.create &.name("router")
        .repository_url("https://gitlab.com/acme/router")

      ids = ShardQuery.new.search("router").to_a.map(&.id)

      ids.should contain(github.id)
      ids.should contain(gitlab.id)
    end

    it "searches by host and owner through the identity" do
      gitlab = ShardFactory.create &.name("router")
        .repository_url("https://gitlab.com/acme/router")
      ShardFactory.create &.name("router")
        .repository_url("https://github.com/kemalcr/router")

      ShardQuery.new.search("gitlab.com/acme").to_a.map(&.id).should eq([gitlab.id])
    end

    it "still matches the description" do
      shard = ShardFactory.create &.name("thing")
        .repository_url("https://github.com/someone/thing")
        .description("A web framework")

      ShardQuery.new.search("web framework").to_a.map(&.id).should eq([shard.id])
    end
  end
end
