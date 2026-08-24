# The console's voice. Every word this product says to a user lives in this
# file, and nothing else in the app carries personality: actions are
# mechanical, the JavaScript renders strings without adding any of its own,
# and the stylesheet carries no copy. Redirecting the personality means
# rewriting this file and only this file.
#
# The register, decided once and applied everywhere:
#
#   warm, playful, a little wry. Never cutesy, never condescending. The
#   reader is smart and new to Crystal, not new to computers. The console is
#   on their side; the compiler's exactness is a fact, not a joke at their
#   expense.
#
# Style rules that hold the register together:
#   Plain words first. Specific over clever. One idea per line. The joke, if
#   there is one, rides at the end and never carries information alone.
module Copy
  # The first thing a new visitor reads, server rendered so it is there
  # before any script runs.
  WELCOME = <<-TEXT
  This is real Crystal, running for real. No signup, no setup, three short
  lessons. Whatever you write in the editor goes to a sandbox, gets compiled
  and run by the actual toolchain, and answers back here.

  Write the line from the lesson on the left, then press Run.
  TEXT

  # For a returning visitor whose progress puts them past the first lesson.
  # Static on purpose: the current lesson's own prompt is shown in the lesson
  # pane, so this line never needs to know which lesson is next.
  WELCOME_BACK = "Welcome back. Your lesson is on the left, where you left it."

  # ---- the workspace chrome ----------------------------------------------
  # Pane titles and controls. Short by design: these are labels on a working
  # surface, not sentences, and a developer reads them once.
  LESSON_PANE_LABEL = "Lesson"
  EDITOR_PANE_LABEL = "Editor"
  OUTPUT_PANE_LABEL = "Output"

  # The editor is multi-line, so Enter belongs to the text and Run belongs to
  # a key you have to mean. Naming the shortcut next to the button is the
  # whole documentation a developer needs.
  RUN_HINT      = "Cmd or Ctrl + Enter"
  COPY_BUTTON   = "Copy example"
  COPIED_NOTICE = "Copied into the editor."
  HINT_LABEL    = "Stuck?"
  EXAMPLE_LABEL = "The line"

  def self.progress_label(position : Int32, total : Int32) : String
    PROGRESS_TEMPLATE.gsub("{n}", position.to_s).gsub("{total}", total.to_s)
  end

  TAGLINE = "Type Crystal. It runs. It answers."
  FOOTER  = "trycrystal.org is a sibling of crystalshards.org, built for the " \
            "Crystal community. The language itself lives at crystal-lang.org."

  # The lesson narrative: position, then what to do.
  #
  # Deliberately WITHOUT the code sample appended. It used to carry it,
  # because the whole lesson arrived as one line in a transcript. The lesson
  # now has its own pane, where the sample is rendered as code in its own
  # block with a button that copies it into the editor, so appending it here
  # would print the same line twice. code_sample is a separate field
  # everywhere it is consumed.
  def self.prompt(lesson : Lesson, position : Int32, total : Int32) : String
    "Lesson #{position} of #{total}. #{lesson.prompt}"
  end

  # Shown when a submission ran cleanly but did not do what the lesson asked.
  def self.not_yet(lesson : Lesson) : String
    "That ran, and nothing broke, but it is not what this lesson asked for. " \
    "#{lesson.hint}"
  end

  # Shown when the compiler or the runtime rejected the submission. The two
  # cases share one line on purpose: the runner reports both as stderr and a
  # non-zero exit, and a framing line that guessed wrong would be worse than
  # one that stays general. The compiler's own words follow immediately.
  SUBMISSION_FAILED = "That one did not survive the compiler. It is not personal, " \
                      "and it happens to everyone who writes Crystal. It says:"

  # Shown when the sandbox stopped a submission and there is no compiler
  # complaint to show for it. Measured case: an endless loop came back with
  # exit 137 (SIGKILL), empty stderr, and timed_out false, and the line
  # above would have blamed the compiler for something the compiler never
  # saw. Keyed on the observable, an empty stderr, rather than on a guess
  # about which signal the sandbox used.
  SANDBOX_STOPPED = "The sandbox stopped that one before it finished, and it left no " \
                    "complaint behind to pass along. Usually that means it never " \
                    "intended to finish. Try something that reaches an end."

  # The one reaction shown for a submission, chosen from what actually
  # happened: passed, missed the point, stopped by the sandbox, rejected by
  # the compiler, or out of clock. All the personality of a round trip
  # funnels through here, so the action above it stays mechanical.
  def self.reaction(result : ExecutionResult, lesson : Lesson, advanced : Bool) : String
    return lesson.success if advanced
    return TIMED_OUT if result.timed_out
    return SANDBOX_STOPPED if !result.ran_clean? && result.stderr.blank?
    return SUBMISSION_FAILED unless result.ran_clean?
    not_yet(lesson)
  end

  # Shown when the sandbox clock ran out before the program did.
  TIMED_OUT = "The sandbox gives every submission a few seconds of clock, and that " \
              "one spent them all. Loops that never end are only fun for the first " \
              "one of them. Try again with one that finishes."

  # Shown when the sandbox could not be reached at all. Nothing ran.
  RUNNER_UNREACHABLE = "The sandbox is not answering right now. Your code did not run, " \
                       "nothing was lost, and it is not anything you typed. Try again " \
                       "in a moment."

  # Shown when an empty submission somehow reaches the server. The console
  # normally stops these in the browser, so arriving here means the page is
  # stale or something is talking to the endpoint directly.
  EMPTY_SUBMISSION = "The console needs actual Crystal to work with. Even one short " \
                     "line will do."

  # Shown when a paste dwarfs the console. The lesson lines are one line
  # each; anything near the limit is a whole file, and the sandbox would
  # time out on it anyway.
  TOO_LARGE = "That submission is far more Crystal than the console can run in one " \
              "go. Try a line, or a few, rather than a file."

  # Shown when the client asks about a lesson this server does not know,
  # which means the page in the tab is older than the code on the server.
  UNKNOWN_LESSON = "This console does not know that lesson, which usually means the " \
                   "page in your tab is older than the server. Reload and pick up " \
                   "where you left off."

  # Shown after the last lesson's check passes. Points somewhere real rather
  # than just applauding.
  FINALE = <<-TEXT
  That is the tour. You typed real Crystal and the real compiler answered,
  three for three. Where to go from here: the language reference is at
  crystal-lang.org, and the packages people build with it are at
  crystalshards.org.

  The console stays open. Keep typing Crystal in it whenever you like.
  TEXT

  # Label prefixed to the inspected value of the final expression, the way a
  # REPL does it.
  VALUE_LABEL = "=>"

  # Chrome rather than voice, but still words the visitor reads, so they
  # still live here. The progress template's {n} and {total} are filled in
  # by the console script; the sentence around them is not negotiable there.
  PROGRESS_TEMPLATE = "Lesson {n} of {total}"
  RUN_BUTTON        = "Run"
  INPUT_LABEL       = "Crystal editor"

  # Shown when the browser cannot even reach this app's own endpoint. The
  # server has its own version for when it reached the endpoint but the
  # sandbox did not answer; the two say the same thing on purpose.
  RUNNER_UNREACHABLE_BROWSER = "The sandbox is not answering right now. Your code " \
                               "did not run, nothing was lost, and it is not anything " \
                               "you typed. Try again in a moment."

  # For a visitor with scripts disabled. Honest about what is missing rather
  # than pretending the page works.
  NOSCRIPT = "This console runs your Crystal in a sandbox and streams the answers " \
             "back, which needs JavaScript. The rest of the page is plain honest HTML."
end
