require "../spec_helper"

# Every example scripts the transport; none of them touches the real API.
# The fixed clock is noon on 2026-08-10 UTC, so a first pass owes exactly
# three days: the 7th (old enough to be final), the 8th and the 9th (still
# being revised by Google).
private NOW = Time.utc(2026, 8, 10, 12, 0, 0)

private alias SearchConsole = CrystalGigs::SearchConsole

private def rows_json(day : String, clicks : Int32 = 3, impressions : Int32 = 40, position : Float64 = 12.5) : String
  %({"rows":[{"keys":["#{day}","crystal docs","https://crystalgigs.com/"],"clicks":#{clicks},"impressions":#{impressions},"ctr":0.075,"position":#{position}}]})
end

# Answers each requested day from a script, recording every request so an
# example can assert what would have gone to Google.
private class ScriptedTransport
  getter requests = [] of SearchConsole::Request

  def initialize(@script : Proc(String, SearchConsole::Response))
  end

  def self.ok(&block : String -> String) : ScriptedTransport
    new(->(body : String) { SearchConsole::Response.new(status: 200, body: block.call(body)) })
  end

  def procure : SearchConsole::Transport
    ->(request : SearchConsole::Request) do
      requests << request
      @script.call(request.body)
    end
  end
end

private def stored_rows
  AppDatabase.query_all(
    "SELECT day, query, page, clicks, impressions, position FROM search_console_daily ORDER BY day",
    as: {Time, String, String, Int64, Int64, Float64}
  )
end

private def claim_row : {Time?, String?}?
  AppDatabase.query_one?(
    "SELECT covered_through, last_error FROM stats_rollups WHERE name = 'search_console'",
    as: {Time?, String?}
  )
end

describe CrystalGigs::SearchConsole do
  before_each do
    AppDatabase.exec("DELETE FROM search_console_daily")
    AppDatabase.exec("DELETE FROM stats_rollups")

    SearchConsole.property = "sc-domain:example.test"
    SearchConsole.clock = -> { NOW }
    SearchConsole.identity = -> { SearchConsole::Identity.new(token: "spec-token", account_email: "gigs-stats@example.test") }
  end

  after_each do
    SearchConsole.property = nil
    SearchConsole.clock = nil
    SearchConsole.identity = nil
    SearchConsole.transport = nil
  end

  describe "a successful pass" do
    it "stores rows for the owed days and settles the oldest" do
      transport = ScriptedTransport.ok { |body| rows_json(body[/\d{4}-\d{2}-\d{2}/]) }
      SearchConsole.transport = transport.procure

      result = SearchConsole.refresh

      result.outcome.should eq(SearchConsole::Outcome::Stored)
      result.days_stored.should eq(3)
      result.rows_stored.should eq(3)

      # The trailing three days, oldest first, each as a one-day query for
      # the configured property, carrying the ambient token.
      transport.requests.map { |request| request.body[/\d{4}-\d{2}-\d{2}/] }
        .should eq(["2026-08-07", "2026-08-08", "2026-08-09"])
      transport.requests.first.url.should contain("sc-domain%3Aexample.test")
      transport.requests.first.token.should eq("spec-token")

      rows = stored_rows
      rows.size.should eq(3)
      rows.first[0].to_s("%F").should eq("2026-08-07")
      rows.first[3].should eq(3_i64)
      rows.first[5].should eq(12.5)

      # Only the 7th is old enough to be final, so coverage stops there even
      # though two newer days were stored.
      covered, last_error = claim_row.not_nil!
      covered.not_nil!.to_s("%F").should eq("2026-08-07")
      last_error.should be_nil
    end

    it "does nothing when called again inside the floor" do
      transport = ScriptedTransport.ok { |body| rows_json(body[/\d{4}-\d{2}-\d{2}/]) }
      SearchConsole.transport = transport.procure

      SearchConsole.refresh
      second = SearchConsole.refresh

      second.outcome.should eq(SearchConsole::Outcome::Skipped)
      transport.requests.size.should eq(3)
      stored_rows.size.should eq(3)
    end

    it "records a day with no impressions as fetched, not as missing" do
      SearchConsole.transport = ScriptedTransport.ok { %({}) }.procure

      result = SearchConsole.refresh

      result.outcome.should eq(SearchConsole::Outcome::Stored)
      result.rows_stored.should eq(0)
      stored_rows.should be_empty

      # Coverage advanced over the empty settled day: a true zero. A day we
      # could not fetch never advances it.
      claim_row.not_nil![0].not_nil!.to_s("%F").should eq("2026-08-07")
    end

    it "upserts, so refetching a recent day revises it instead of duplicating it" do
      first = ScriptedTransport.ok { |body| rows_json(body[/\d{4}-\d{2}-\d{2}/]) }
      SearchConsole.transport = first.procure
      SearchConsole.refresh

      # Two hours later, same day: the floor has passed, and the two
      # unsettled days are owed again. Google has revised the 8th upward.
      SearchConsole.clock = -> { NOW + 2.hours }
      second = ScriptedTransport.ok { |body|
        day = body[/\d{4}-\d{2}-\d{2}/]
        day == "2026-08-08" ? rows_json(day, clicks: 9, impressions: 90, position: 8.25) : rows_json(day)
      }
      SearchConsole.transport = second.procure

      result = SearchConsole.refresh

      result.outcome.should eq(SearchConsole::Outcome::Stored)
      result.days_stored.should eq(2)
      first.requests.size.should eq(3)
      second.requests.size.should eq(2)

      rows = stored_rows
      rows.size.should eq(3)
      revised_row = rows.find { |row| row[0].to_s("%F") == "2026-08-08" }.not_nil!
      revised_row[3].should eq(9_i64)
      revised_row[5].should eq(8.25)
    end
  end

  describe "a pass the API refuses" do
    it "reports a 403 as an access problem naming the account and the property, never as empty data" do
      SearchConsole.transport = ScriptedTransport.new(->(body : String) {
        SearchConsole::Response.new(status: 403, body: %({"error":{"message":"User does not have sufficient permission for site"}}))
      }).procure

      result = SearchConsole.refresh

      result.outcome.should eq(SearchConsole::Outcome::Failed)
      error = result.error.not_nil!
      error.should contain("gigs-stats@example.test")
      error.should contain("sc-domain:example.test")

      # Nothing was stored and coverage did not move, so the page cannot
      # mistake a missing grant for a quiet day.
      stored_rows.should be_empty
      covered, last_error = claim_row.not_nil!
      covered.should be_nil
      last_error.not_nil!.should contain("gigs-stats@example.test")
      last_error.not_nil!.should contain("sc-domain:example.test")

      status = SearchConsole.status
      status.failing?.should be_true
      status.covered_through.should be_nil
    end

    it "keeps prior rows when a later day in the pass fails" do
      SearchConsole.transport = ScriptedTransport.new(->(body : String) {
        if body.includes?("2026-08-08")
          SearchConsole::Response.new(status: 500, body: "backend exploded")
        else
          SearchConsole::Response.new(status: 200, body: rows_json(body[/\d{4}-\d{2}-\d{2}/]))
        end
      }).procure

      result = SearchConsole.refresh

      result.outcome.should eq(SearchConsole::Outcome::Failed)
      result.error.not_nil!.should contain("HTTP 500")

      # The 7th committed before the 8th failed, and the 9th was never
      # asked for.
      rows = stored_rows
      rows.size.should eq(1)
      rows.first[0].to_s("%F").should eq("2026-08-07")
      claim_row.not_nil![0].not_nil!.to_s("%F").should eq("2026-08-07")
      claim_row.not_nil![1].not_nil!.should contain("HTTP 500")
    end

    it "heals the gap on the next pass once the API answers again" do
      SearchConsole.transport = ScriptedTransport.new(->(body : String) {
        if body.includes?("2026-08-08")
          SearchConsole::Response.new(status: 500, body: "backend exploded")
        else
          SearchConsole::Response.new(status: 200, body: rows_json(body[/\d{4}-\d{2}-\d{2}/]))
        end
      }).procure
      SearchConsole.refresh

      SearchConsole.clock = -> { NOW + 2.hours }
      SearchConsole.transport = ScriptedTransport.ok { |body| rows_json(body[/\d{4}-\d{2}-\d{2}/]) }.procure

      result = SearchConsole.refresh

      result.outcome.should eq(SearchConsole::Outcome::Stored)
      result.days_stored.should eq(2)
      stored_rows.size.should eq(3)

      # The failure is cleared by the completed pass; coverage stays at the
      # 7th because the 8th is still being revised by Google.
      claim_row.not_nil![1].should be_nil
      claim_row.not_nil![0].not_nil!.to_s("%F").should eq("2026-08-07")
    end
  end

  describe "not configured" do
    it "is off, spends nothing, and says so" do
      SearchConsole.property = ""
      called = false
      SearchConsole.transport = ->(request : SearchConsole::Request) {
        called = true
        SearchConsole::Response.new(status: 200, body: %({}))
      }

      result = SearchConsole.refresh

      result.outcome.should eq(SearchConsole::Outcome::Disabled)
      called.should be_false

      status = SearchConsole.status
      status.configured?.should be_false
      status.property.should be_nil
    end
  end

  describe "status before any pass" do
    it "is pending: configured, no data, no error, none of which is zero traffic" do
      status = SearchConsole.status

      status.configured?.should be_true
      status.property.should eq("sc-domain:example.test")
      status.pending?.should be_true
      status.covered_through.should be_nil
      status.last_error.should be_nil
    end
  end
end
