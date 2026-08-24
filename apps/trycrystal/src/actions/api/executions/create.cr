# The console's one endpoint: run this submission against the current
# lesson, then say what happened.
#
# The request is {"code": "...", "lesson_id": "..."} and the response is the
# runner's answer passed through untouched (stdout, stderr, value,
# exit_code, timed_out, duration_ms: all strings the browser renders as
# text) plus a "lesson" object carrying the verdict: whether the check
# advanced, the reaction in the console's voice, and, on advancement, the
# next lesson to prompt with.
#
# Everything a user's code produced is data in JSON, never HTML: the page
# renders it exclusively through textContent, and this side never marks it
# up either.
class Api::Executions::Create < ApiAction
  # Generous for a lesson console: the lesson lines are one line each, and
  # anything near this size is a paste of a whole file, which the sandbox
  # would time out on anyway. Refusing it here saves the round trip.
  MAX_CODE_BYTES = 65_536

  post "/api/executions" do
    code, lesson_id = read_submission

    if code.nil?
      return json({error: "bad_request", message: Copy::EMPTY_SUBMISSION}, status: 400)
    end

    # Empty string, not nil: a body that parsed but carried nothing to run.
    if code.blank?
      return json({error: "empty_submission", message: Copy::EMPTY_SUBMISSION}, status: 400)
    end

    if code.bytesize > MAX_CODE_BYTES
      return json({error: "too_large", message: Copy::TOO_LARGE}, status: 413)
    end

    # No lesson id is a legitimate submission, not an error: after the last
    # lesson the console stays open as a plain REPL, and the copy promises
    # exactly that. An id that no lesson answers to is a different thing,
    # a page older than the server, and it says so.
    lesson = Lessons.find(lesson_id)
    if lesson.nil? && !lesson_id.nil?
      return json({error: "unknown_lesson", message: Copy::UNKNOWN_LESSON}, status: 422)
    end

    result = RunnerClient.new.execute(code)

    # stdout and stderr are sent BOTH ways: the plain string, unchanged, and
    # a segment list with the compiler's ANSI colours parsed out of it. The
    # browser renders segments when they are present and falls back to the
    # string when they are not, so a client that knows nothing about segments
    # still shows correct text.
    #
    # The escapes have to be handled somewhere: the compiler emits them, and
    # rendered as text they arrive on the page as literal "[2m" noise. Parsing
    # here keeps the browser rendering strings rather than authoring markup,
    # which is the rule that keeps this console from growing an XSS hole.
    json({
      stdout:          result.stdout,
      stderr:          result.stderr,
      stdout_segments: Ansi.parse(result.stdout),
      stderr_segments: Ansi.parse(result.stderr),
      value:           result.value,
      exit_code:       result.exit_code,
      timed_out:       result.timed_out,
      duration_ms:     result.duration_ms,
      lesson:          lesson.try { |current| verdict(current, result) },
    })
  rescue ex : RunnerClient::Unreachable
    Log.warn { "sandbox unreachable: #{ex.message}" }
    json({error: "runner_unreachable", message: Copy::RUNNER_UNREACHABLE}, status: 502)
  rescue ex : RunnerClient::BadResponse
    Log.error { "sandbox broke the contract: #{ex.message}" }
    json({error: "runner_unreachable", message: Copy::RUNNER_UNREACHABLE}, status: 502)
  end

  # The lesson half of the answer: did this result satisfy the lesson, what
  # does the console say about it, and what comes next.
  private def verdict(lesson : Lesson, result : ExecutionResult)
    advanced = lesson.check.call(result)
    next_lesson = advanced ? Lessons.after(lesson.id) : nil

    {
      id:       lesson.id,
      advanced: advanced,
      finished: advanced && next_lesson.nil?,
      reaction: Copy.reaction(result, lesson, advanced),
      next:     next_lesson.try(&.public_payload),
    }
  end

  # Reads the JSON body and returns the code and lesson id. Nil code means
  # the body was not a submission at all: not JSON, or missing the code
  # field, or code was not a string. Distinctions below that do not change
  # what the visitor sees, so they are deliberately not made.
  private def read_submission : {String?, String?}
    payload = params.from_json
    code = payload["code"]?.try &.as_s?
    lesson_id = payload["lesson_id"]?.try &.as_s?
    {code, lesson_id}
  end
end
