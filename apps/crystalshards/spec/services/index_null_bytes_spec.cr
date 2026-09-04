require "../spec_helper"

# Required directly, for the same reason shard_indexer_spec.cr requires it:
# src/app.cr carries only version_order out of services/, because indexing runs
# in a Cloud Run Job rather than in the web server.
require "../../src/services/shard_indexer"

# A repository whose text carries a NUL byte.
#
# Not hypothetical: github.com/dogwaterdev1/rock_paper_scissor is a live
# repository with one tag whose README.md at v1.0.0 is 859 bytes carrying 22 of
# them, and crystalshards.org has never once managed to index it. Postgres
# rejects the byte outright, the write raised PQ::PQError from inside the store
# transaction, and PQ::PQError is not the Avram::InvalidOperationError the
# version writes rescue, so the exception escaped the whole pass. The row was
# left mid-pass with no versions, no repository facts, and no recorded reason,
# and every later pass reproduced it exactly.
#
# The scrub belongs at the boundary the bytes arrive at, so this drives the
# real GithubRepositoryApi through RecordedGithub rather than asserting on
# HostText directly: what matters is that a pass over such a repository
# finishes and stores something a reader can read.
describe "indexing a repository whose text carries NUL bytes" do
  it "stores the README with the NULs removed and finishes the pass" do
    shard = ShardFactory.create &.name("rock-paper-scissors")
      .at("github.com", "dogwaterdev1", "rock_paper_scissor")

    readme = "# Rock\u0000 Paper\u0000 Scissors\u0000"
    manifest = <<-YAML
      name: rock-paper-scissors
      version: 1.0.0
      license: MIT
      YAML

    github = RecordedGithub.new("dogwaterdev1/rock_paper_scissor")
      .repository(stars: 3, description: "A game\u0000 in Crystal", default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", manifest)
      .file("v1.0.0", "README.md", readme)

    result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

    result.outcome.should eq(ShardIndexer::Outcome::Indexed)

    stored = ShardQuery.new.id(shard.id).first
    stored.readme_content.should eq("# Rock Paper Scissors")
    stored.description.should eq("A game in Crystal")
    stored.indexed_at.should_not be_nil
    stored.latest_version.should eq("1.0.0")

    versions = ShardVersionQuery.new.shard_id(shard.id).to_a
    versions.map(&.version).should eq(["1.0.0"])
  end

  it "keeps a NUL out of a stored manifest, which is a text column too" do
    shard = ShardFactory.create &.name("nulled").at("github.com", "acme", "nulled")

    github = RecordedGithub.new("acme/nulled")
      .repository(default_branch: "main")
      .tags("v0.1.0")
      .file("v0.1.0", "shard.yml", "name: nulled\u0000\nversion: 0.1.0\n")

    RecordedGithub.install(github) { ShardIndexer.index(shard) }

    version = ShardVersionQuery.new.shard_id(shard.id).version("0.1.0").first
    version.spec_yaml.should eq("name: nulled\nversion: 0.1.0\n")
  end
end
