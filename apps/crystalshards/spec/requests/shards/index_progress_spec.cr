require "../../spec_helper"

# What a visitor watching an unindexed shard is shown.
#
# Landing on a shard discovery has found but nothing has read commissions an
# index pass, and the page said one sentence for the whole of it: reading the
# repository, then its shard.yml and README, then writing versions, then
# resolving the dependency graph. Same complaint the documentation build had.
private def unread_shard(step : String? = nil) : Shard
  shard = ShardFactory.create &.name("unread-progress")
    .repository_url("https://github.com/acme/unread-progress")
    .canonical_slug("github.com/acme/unread-progress")

  AppDatabase.exec("UPDATE shards SET index_step = $1 WHERE id = $2", step, shard.id)
  ShardQuery.new.id(shard.id).first
end

describe "indexing progress" do
  it "lists every step from the start, so the list does not grow under the visitor" do
    unread_shard("reading")

    response = BrowserClient.exec(Shards::Show.with(host: "github.com", owner: "acme", repo: "unread-progress"))

    response.status_code.should eq(200)
    ShardIndexer::IndexSteps::ALL.each do |step|
      response.body.should contain(step.label)
    end
  end

  it "marks the reported step as current and the ones before it as done" do
    unread_shard("recording")

    response = BrowserClient.exec(Shards::Show.with(host: "github.com", owner: "acme", repo: "unread-progress"))

    states = response.body.scan(/index-step (is-[a-z]+)/).map(&.[1])
    states.should eq(["is-done", "is-done", "is-current", "is-waiting"])
  end

  it "marks nothing done when the pass has not reported a step yet" do
    # The first moments of every pass, and the permanent state of one whose
    # step writes were all lost.
    unread_shard(nil)

    response = BrowserClient.exec(Shards::Show.with(host: "github.com", owner: "acme", repo: "unread-progress"))

    response.body.should contain("Reading the repository")
    response.body.should_not contain("index-step is-done")
    response.body.should_not contain("index-step is-current")
  end
end
