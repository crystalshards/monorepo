require "../spec_helper"

# The lesson checks are the tutorial's entire notion of progress, so they
# are proven directly against crafted results: each lesson advances on the
# behavior it teaches, refuses a clean run that missed the point, and
# refuses a crash that printed the right words on its way down. The checks
# never see source code, which is also why no spec here mentions any.
describe "lesson checks" do
  lesson_one = Lessons.find("say-hello").not_nil!
  lesson_two = Lessons.find("strings-answer").not_nil!
  lesson_three = Lessons.find("braid-them").not_nil!

  it "advances lesson one on the printed greeting" do
    result = ExecutionResult.new(
      stdout: "Hello, Crystal!\n", stderr: "", value: nil,
      exit_code: 0, timed_out: false, duration_ms: 401_i64
    )

    lesson_one.check.call(result).should be_true
  end

  it "refuses lesson one when the right words came out of a crashing program" do
    result = ExecutionResult.new(
      stdout: "Hello, Crystal!\n", stderr: "unhandled exception",
      value: nil, exit_code: 1, timed_out: false, duration_ms: 401_i64
    )

    lesson_one.check.call(result).should be_false
  end

  it "refuses lesson one when nothing was printed" do
    result = ExecutionResult.new(
      stdout: "Goodbye\n", stderr: "", value: nil,
      exit_code: 0, timed_out: false, duration_ms: 401_i64
    )

    lesson_one.check.call(result).should be_false
  end

  it "advances lesson two on the inspected value, quotes included by the runner" do
    # The runner inspects the final expression, so a String value arrives
    # quoted. The check must see through that, because the lesson asked for
    # the string, not for its inspect rendering.
    result = ExecutionResult.new(
      stdout: "", stderr: "", value: %("HELLO, CRYSTAL!"),
      exit_code: 0, timed_out: false, duration_ms: 401_i64
    )

    lesson_two.check.call(result).should be_true
  end

  it "advances lesson two when the greeting was printed instead of returned" do
    # Behavior over spelling: a visitor who puts the shout still learned
    # the lesson, and the value alone is not the point.
    result = ExecutionResult.new(
      stdout: "HELLO, CRYSTAL!\n", stderr: "", value: nil,
      exit_code: 0, timed_out: false, duration_ms: 401_i64
    )

    lesson_two.check.call(result).should be_true
  end

  it "refuses lesson two on the untouched string" do
    result = ExecutionResult.new(
      stdout: "", stderr: "", value: %("Hello, Crystal!"),
      exit_code: 0, timed_out: false, duration_ms: 401_i64
    )

    lesson_two.check.call(result).should be_false
  end

  it "advances lesson three on the composed line, tolerating surrounding blank lines" do
    result = ExecutionResult.new(
      stdout: "Hello, CRYSTAL!\n", stderr: "", value: "nil",
      exit_code: 0, timed_out: false, duration_ms: 401_i64
    )

    lesson_three.check.call(result).should be_true
  end

  it "refuses lesson three on the quiet greeting" do
    result = ExecutionResult.new(
      stdout: "Hello, Crystal!\n", stderr: "", value: nil,
      exit_code: 0, timed_out: false, duration_ms: 401_i64
    )

    lesson_three.check.call(result).should be_false
  end

  it "refuses every lesson when the clock ran out" do
    result = ExecutionResult.new(
      stdout: "Hello, Crystal!\n", stderr: "", value: nil,
      exit_code: 124, timed_out: true, duration_ms: 5000_i64
    )

    Lessons::ALL.each do |lesson|
      lesson.check.call(result).should be_false
    end
  end
end

describe "the tutorial's order" do
  it "has three lessons, each building on the last" do
    Lessons.total.should eq 3
    Lessons::ALL.map(&.id).should eq ["say-hello", "strings-answer", "braid-them"]
  end

  it "knows what follows what" do
    Lessons.after("say-hello").try(&.id).should eq "strings-answer"
    Lessons.after("strings-answer").try(&.id).should eq "braid-them"
    Lessons.after("braid-them").should be_nil
  end

  it "finds and positions lessons by id, and nothing else" do
    Lessons.position_of("say-hello").should eq 1
    Lessons.position_of("braid-them").should eq 3
    Lessons.position_of("no-such-lesson").should be_nil
    Lessons.find("no-such-lesson").should be_nil
    Lessons.find(nil).should be_nil
  end

  it "composes each lesson's prompt with its position and code sample" do
    prompt = Copy.prompt(Lessons.find("strings-answer").not_nil!, 2, 3)

    prompt.should start_with("Lesson 2 of 3.")
    prompt.should contain(%("Hello, Crystal!".upcase))
  end
end
