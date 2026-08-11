require "../spec_helper"

# The row exists to answer one question honestly: can the registry's view of this
# host be trusted as complete. These examples are about that answer, because
# "the command exited 0" and "we have seen the host" are different things.
describe CrawlState do
  it "only calls a sweep trustworthy when it finished AND could see the whole host" do
    exhaustive = SaveCrawlState.create!(
      host: "github.com",
      status: CrawlState::Status::COMPLETED,
      stop_reason: CrawlState::StopReason::COMPLETED_EXHAUSTIVE,
    )
    exhaustive.trustworthy?.should be_true

    # Ran to the end of what it could ask for, which is not the whole host.
    topic_scoped = SaveCrawlState.create!(
      host: "gitlab.com",
      status: CrawlState::Status::PARTIAL,
      stop_reason: CrawlState::StopReason::COMPLETED_TOPIC_SCOPED,
    )
    topic_scoped.trustworthy?.should be_false

    rate_limited = SaveCrawlState.create!(
      host: "codeberg.org",
      status: CrawlState::Status::PARTIAL,
      stop_reason: CrawlState::StopReason::RATE_LIMITED,
      cursor: "3",
    )
    rate_limited.trustworthy?.should be_false
    rate_limited.resumable?.should be_true
  end

  it "is resumable exactly when it has a cursor" do
    SaveCrawlState.create!(host: "github.com", status: CrawlState::Status::IDLE).resumable?.should be_false
    SaveCrawlState.create!(host: "gitlab.com", status: CrawlState::Status::PARTIAL, cursor: "7").resumable?.should be_true
  end

  it "holds one row per host" do
    SaveCrawlState.create!(host: "github.com", status: CrawlState::Status::IDLE)

    # Two sweeps of one host must not each keep their own idea of the cursor.
    expect_raises(Avram::InvalidOperationError) do
      SaveCrawlState.create!(host: "github.com", status: CrawlState::Status::IDLE)
    end
  end

  it "refuses a status that is not one of the five" do
    expect_raises(Avram::InvalidOperationError) do
      SaveCrawlState.create!(host: "github.com", status: "sort of finished")
    end
  end

  it "truncates a host's error page instead of storing all of it" do
    state = SaveCrawlState.create!(
      host: "github.com",
      status: CrawlState::Status::FAILED,
      last_error: "x" * 2_000,
    )

    state.last_error.to_s.size.should eq(SaveCrawlState::MAX_ERROR_LENGTH)
  end

  it "summarises itself for an operator reading logs" do
    state = SaveCrawlState.create!(
      host: "gitlab.com",
      status: CrawlState::Status::PARTIAL,
      stop_reason: CrawlState::StopReason::RATE_LIMITED,
      cursor: "4",
      discovered_count: 12_i64,
      updated_count: 3_i64,
      unavailable_count: 1_i64,
    )

    summary = state.summary_line
    summary.should contain("gitlab.com: partial")
    summary.should contain("discovered 12")
    summary.should contain("unavailable 1")
    summary.should contain("rate_limited")
    summary.should contain("resumes from cursor")
  end
end
