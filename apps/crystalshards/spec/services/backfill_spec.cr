require "../spec_helper"

# The migration's backfill, exercised as the migration runs it: rows are read,
# ShardIdentity.backfill_plan works out what each one's identity is, and the
# statements it produces are executed against the real table.
#
# Legacy rows are inserted with raw SQL on purpose. SaveShard now refuses a
# shard without an identity, so a pre-identity row cannot be created through
# the operation, which is exactly the situation the backfill exists for.
def insert_legacy_row(name : String, repository_url : String) : Int64
  AppDatabase.query_one(
    <<-SQL,
    INSERT INTO shards
      (name, repository_url, provider, repository_type, total_downloads, created_at, updated_at)
    VALUES ($1, $2, 'github', 'git', 0, NOW(), NOW())
    RETURNING id
    SQL
    name, repository_url, as: Int64
  )
end

def row_identity(id : Int64)
  AppDatabase.query_one(
    "SELECT host, owner, repo, canonical_slug FROM shards WHERE id = $1",
    id, as: {String?, String?, String?, String?}
  )
end

def run_backfill
  rows = AppDatabase.query_all(
    "SELECT id, name, repository_url FROM shards WHERE canonical_slug IS NULL ORDER BY id",
    as: {Int64, String, String}
  ).map do |(id, name, repository_url)|
    ShardIdentity::LegacyRow.new(id: id, name: name, repository_url: repository_url)
  end

  plan = ShardIdentity.backfill_plan(rows)
  plan.statements.each { |statement| AppDatabase.exec(statement) }
  plan
end

describe "identity backfill" do
  it "fills in the identity of every row whose URL names a repository" do
    plain = insert_legacy_row("kemal", "https://github.com/kemalcr/kemal")
    dot_git = insert_legacy_row("lucky", "https://github.com/luckyframework/lucky.git")
    other_host = insert_legacy_row("router", "https://gitlab.com/acme/router")
    dotted_name = insert_legacy_row("jennifer", "https://github.com/imdrasil/jennifer.cr")

    plan = run_backfill

    plan.unparseable.should be_empty
    plan.updated_count.should eq(4)

    row_identity(plain).should eq({"github.com", "kemalcr", "kemal", "github.com/kemalcr/kemal"})
    row_identity(dot_git).should eq(
      {"github.com", "luckyframework", "lucky", "github.com/luckyframework/lucky"}
    )
    row_identity(other_host).should eq({"gitlab.com", "acme", "router", "gitlab.com/acme/router"})
    row_identity(dotted_name).should eq(
      {"github.com", "imdrasil", "jennifer.cr", "github.com/imdrasil/jennifer.cr"}
    )
  end

  # The case the report has to be honest about. This URL is a user page, not a
  # repository, so there is no identity to be had from it.
  it "reports a URL it cannot parse and leaves that row untouched" do
    good = insert_legacy_row("fine", "https://github.com/someone/fine")
    bad = insert_legacy_row("broken", "https://github.com/just-an-owner")

    plan = run_backfill

    plan.updated_count.should eq(1)
    plan.unparseable.map(&.id).should eq([bad])
    plan.unparseable.first.name.should eq("broken")
    plan.unparseable.first.repository_url.should eq("https://github.com/just-an-owner")

    row_identity(good).should eq({"github.com", "someone", "fine", "github.com/someone/fine"})

    # Not dropped, not guessed at: still there, still nameable, no identity.
    row_identity(bad).should eq({nil, nil, nil, nil})
    AppDatabase.query_one("SELECT name FROM shards WHERE id = $1", bad, as: String).should eq("broken")
  end

  it "reports every unparseable shape without touching any of them" do
    urls = {
      "no-repo"    => "https://github.com",
      "owner-only" => "https://github.com/owner",
      "deep-path"  => "https://gitlab.com/group/subgroup/project",
      "not-a-url"  => "file:///opt/src/thing",
      "tree-path"  => "https://github.com/owner/repo/tree/master",
    }
    ids = urls.map { |name, url| insert_legacy_row(name, url) }

    plan = run_backfill

    plan.updated_count.should eq(0)
    plan.unparseable.map(&.id).sort.should eq(ids.sort)
    ids.each { |id| row_identity(id).should eq({nil, nil, nil, nil}) }
  end

  it "leaves a row that already has an identity alone" do
    already = ShardFactory.create &.name("done")
      .repository_url("https://github.com/someone/done")

    plan = run_backfill

    plan.total.should eq(0)
    ShardQuery.new.id(already.id).first.canonical_slug.should eq("github.com/someone/done")
  end

  it "makes a backfilled row reachable at its canonical URL" do
    id = insert_legacy_row("reachable", "https://codeberg.org/person/reachable")
    run_backfill

    shard = ShardQuery.new.id(id).first
    response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

    response.status_code.should eq(200)
    response.body.should contain("codeberg.org/person/reachable")
  end

  # A row the backfill could not identify still has to be readable somewhere,
  # and its only address has always been its name.
  it "serves a row with no identity at its legacy name URL" do
    insert_legacy_row("orphan", "https://github.com/just-an-owner")

    response = BrowserClient.exec(Shards::ShowByName.with(shard_name: "orphan"))

    response.status_code.should eq(200)
    response.body.should contain("orphan")
  end
end
