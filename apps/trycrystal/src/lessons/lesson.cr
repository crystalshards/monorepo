require "json"

# What came back from the sandbox after running a submission. This is the
# runner's contract verbatim (see DESIGN.md): stdout, stderr, the inspected
# value of the final expression, the exit code, whether the clock ran out,
# and how long the whole thing took.
#
# An error in the user's code is a perfectly healthy result: it arrives with
# stderr populated and a non-zero exit_code. Only the web app failing to
# reach the runner at all is a transport problem, and that is raised as an
# exception before one of these is ever built.
struct ExecutionResult
  include JSON::Serializable

  property stdout : String
  property stderr : String
  property value : String?
  property exit_code : Int32
  property timed_out : Bool
  property duration_ms : Int64

  def initialize(@stdout : String, @stderr : String, @value : String?,
                 @exit_code : Int32, @timed_out : Bool, @duration_ms : Int64)
  end

  # The submission ran to completion and the program exited cleanly. A
  # lesson check that forgot this would advance on a program that crashed
  # after printing the expected words.
  def ran_clean? : Bool
    !timed_out && exit_code.zero?
  end

  # The runner inspects the final expression, so a String arrives with its
  # inspect quoting attached: "HELLO, CRYSTAL!" including the quotes. Checks
  # compare against what the expression was, not against how inspect chose
  # to render it, so the quoting comes off here.
  def unquoted_value : String?
    raw = value
    return nil if raw.nil?
    if raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"')
      raw[1..-2]
    else
      raw
    end
  end
end

# One step of the tutorial. A lesson owns, in order of importance:
#
#   check       decides, from the ExecutionResult alone, whether the user
#               advances. It never sees the source that was submitted: two
#               spellings that behave the same both pass, and a copy of the
#               sample line that behaves differently still fails.
#   prompt      what to do and why it matters (prose, no code).
#   code_sample the exact line to type, shown on its own line.
#   hint        the nudge shown when a submission ran but missed the point.
#   success     the reaction when the check passes.
#
# All five are words a visitor reads, so the lesson text itself is passed in
# from Copy rather than written here; this file is structure only.
struct Lesson
  getter id : String
  getter prompt : String
  getter code_sample : String
  getter hint : String
  getter success : String
  getter check : Proc(ExecutionResult, Bool)

  def initialize(@id : String, @prompt : String, @code_sample : String,
                 @hint : String, @success : String,
                 @check : Proc(ExecutionResult, Bool))
  end

  # The JSON the browser keeps for this lesson: everything the console needs
  # to resume mid-tutorial without another round trip, and nothing it does
  # not. The check deliberately stays server side, so what counts as
  # passing is never decided in the browser.
  def public_payload : NamedTuple
    position = Lessons.position_of(id) || 1
    {
      id:          id,
      prompt:      Copy.prompt(self, position, Lessons.total),
      code_sample: code_sample,
      hint:        hint,
    }
  end
end
