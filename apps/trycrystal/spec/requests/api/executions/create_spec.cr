require "../../../spec_helper"

# The console's one endpoint, exercised against a real fake sandbox over a
# real socket. What is proven here:
#
#   the runner's answer passes through untouched, as data;
#   the check verdict and the next lesson ride along;
#   every failure mode the runner can produce gets in-character copy, not a
#   stack trace, including the runner being gone entirely.
describe Api::Executions::Create do
  it "runs a submission for the current lesson and advances it" do
    FakeRunner.stub(stdout: "Hello, Crystal!\n")

    response = submit(%(puts "Hello, Crystal!"), "say-hello")

    response.status_code.should eq 200
    response.should send_json(200, stdout: "Hello, Crystal!\n", exit_code: 0)

    body = JSON.parse(response.body)
    body["lesson"]["id"].should eq "say-hello"
    body["lesson"]["advanced"].should be_true
    body["lesson"]["finished"].should be_false
    body["lesson"]["next"]["id"].should eq "strings-answer"
    body["lesson"]["next"]["prompt"].as_s.should contain("upcase")
  end

  it "marks the final lesson finished rather than naming a next one" do
    FakeRunner.stub(stdout: "Hello, CRYSTAL!\n")

    response = submit(%(puts "Hello, #{"Crystal".upcase}!"), "braid-them")

    body = JSON.parse(response.body)
    body["lesson"]["advanced"].should be_true
    body["lesson"]["finished"].should be_true
    body["lesson"]["next"]?.try(&.raw).should be_nil
  end

  it "runs a submission with no lesson at all, once the tutorial is done" do
    # The finale copy promises the console stays open, so a submission with
    # no lesson id is a plain REPL run: output, no verdict. Answering 422
    # here is what wedged a finished console in the browser.
    FakeRunner.stub(stdout: "42\n", value: "42")

    response = ApiClient.new.exec_raw(
      Api::Executions::Create,
      {code: "puts 6 * 7"}.to_json
    )

    response.status_code.should eq 200
    body = JSON.parse(response.body)
    body["stdout"].should eq "42\n"
    body["lesson"].raw.should be_nil
  end

  it "carries hostile output as data, byte for byte, never as markup" do
    # The transport half of the escaping story: whatever the sandbox printed
    # arrives in the JSON exactly as it left. The rendering half, that the
    # console paints it as text rather than HTML, is the page's contract and
    # is proven in the browser, but this pins the server side of it: no
    # sanitizing, no stripping, no double-decoding on the way through.
    hostile = %(<script>alert("pwn")</script> <img src=x onerror=alert(1)>)
    FakeRunner.stub(stdout: hostile, value: hostile)

    response = submit(%(puts "<script>alert(1)</script>"), "say-hello")

    response.status_code.should eq 200
    body = JSON.parse(response.body)
    body["stdout"].as_s.should eq hostile
    body["value"].as_s.should eq hostile
  end

  it "nudges, with the hint, when the code ran but missed the point" do
    FakeRunner.stub(stdout: "Goodbye\n")

    response = submit(%(puts "Goodbye"), "say-hello")

    body = JSON.parse(response.body)
    body["lesson"]["advanced"].should be_false
    reaction = body["lesson"]["reaction"].as_s
    reaction.should contain("not what this lesson asked for")
    reaction.should contain("spelling is not one of them")
  end

  it "frames a failed compilation with the compiler's own words after it" do
    FakeRunner.stub(
      stdout: "",
      stderr: "error in line 1: unterminated string\n",
      exit_code: 1
    )

    response = submit(%(puts "oops), "say-hello")

    body = JSON.parse(response.body)
    body["stderr"].as_s.should contain("unterminated string")
    reaction = body["lesson"]["reaction"].as_s
    reaction.should contain("did not survive the compiler")
    body["lesson"]["advanced"].should be_false
  end

  it "explains a timeout rather than reporting it as a crash" do
    FakeRunner.stub(stdout: "", exit_code: 124, timed_out: true, duration_ms: 5000_i64)

    response = submit("loop { }", "say-hello")

    body = JSON.parse(response.body)
    body["timed_out"].should be_true
    body["lesson"]["reaction"].as_s.should contain("spent them all")
  end

  it "does not blame the compiler for a submission the sandbox killed" do
    # Measured against the real sandbox: an endless loop came back exit 137
    # with empty stderr and timed_out false, and the compiler framing would
    # have been a lie about code the compiler accepted.
    FakeRunner.stub(stdout: "", stderr: "", exit_code: 137, duration_ms: 14_967_i64)

    response = submit("loop { }", "say-hello")

    body = JSON.parse(response.body)
    reaction = body["lesson"]["reaction"].as_s
    reaction.should contain("sandbox stopped that one")
    reaction.should_not contain("compiler")
  end

  it "answers in character, with 502, when the sandbox is unreachable" do
    RunnerClient.temp_config(url: FakeRunner.dead_url) do
      response = submit(%(puts "Hello, Crystal!"), "say-hello")

      response.status_code.should eq 502
      body = JSON.parse(response.body)
      body["error"].should eq "runner_unreachable"
      body["message"].as_s.should contain("sandbox is not answering")
    end
  end

  it "refuses a submission from a lesson it does not know" do
    FakeRunner.stub(stdout: "Hello, Crystal!\n")

    response = submit(%(puts "Hello, Crystal!"), "a-lesson-that-was-removed")

    response.status_code.should eq 422
    JSON.parse(response.body)["message"].as_s.should contain("older than the server")
  end

  it "refuses a body that is not a submission" do
    # Lucky rejects the malformed JSON itself, before the action's own
    # guards: a 400 with a parse message rather than anything the console
    # would show. That is the right division of labor, so this pins it.
    response = ApiClient.new.exec_raw(Api::Executions::Create, "this is not json")

    response.status_code.should eq 400
    JSON.parse(response.body)["error"].as_s.should contain("parsing the JSON")
  end

  it "refuses a submission with no code" do
    response = submit("", "say-hello")

    response.status_code.should eq 400
    JSON.parse(response.body)["error"].should eq "empty_submission"
  end

  it "refuses a paste far larger than any lesson line" do
    wall_of_code = ("puts 1 # " * 9_000)

    response = submit(wall_of_code, "say-hello")

    response.status_code.should eq 413
    JSON.parse(response.body)["error"].should eq "too_large"
  end
end

private def submit(code : String, lesson_id : String)
  ApiClient.new.exec_raw(
    Api::Executions::Create,
    {code: code, lesson_id: lesson_id}.to_json
  )
end
