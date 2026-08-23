# The whole product is this page: a masthead, a transcript, and a place to
# type. The transcript is server rendered for the first two lines (the
# welcome and lesson one's prompt) so a visitor sees real content before any
# script runs, and every line after that is appended by console.js.
#
# Two rules hold the page together:
#
#   Everything a visitor's code produced, or a visitor typed, moves as JSON
#   and is rendered with textContent. Nothing in this page or in console.js
#   builds markup from it, so it can never become HTML.
#
#   Every word the page says comes from Copy. This file is structure only.
class Home::IndexPage < MainLayout
  def page_title
    "try Crystal, a console that talks back"
  end

  def content
    header class: "masthead" do
      tag "div", class: "brand" do
        mount Mark
        span "try crystal", class: "wordmark"
      end
      para Copy::TAGLINE, class: "tagline"

      tag "div", class: "progress", id: "progress" do
        span Copy.progress_label(1, Lessons.total), class: "progress-label"
        tag "div", class: "steps", "aria-hidden": "true" do
          Lessons::ALL.each_with_index do |lesson, index|
            classes = index.zero? ? "step step--current" : "step"
            span "", class: classes, "data-step": lesson.id
          end
        end
      end
    end

    tag "section", class: "console", "aria-label": "Crystal console" do
      tag "div", class: "transcript", id: "transcript", role: "log", "aria-live": "polite" do
        line "system", Copy::WELCOME
        line "lesson", Copy.prompt(Lessons.first, 1, Lessons.total)
      end

      tag "form", class: "entry", id: "console-form" do
        label Copy::INPUT_LABEL, for: "console-input", class: "visually-hidden"
        span "001>", class: "counter", id: "counter", "aria-hidden": "true"
        textarea "", id: "console-input", class: "input", rows: "1",
          spellcheck: "false", autocapitalize: "off", autocomplete: "off",
          wrap: "soft", autofocus: "autofocus"
        tag "button", type: "submit", class: "run" do
          text Copy::RUN_BUTTON
        end
      end

      noscript do
        text Copy::NOSCRIPT
      end
    end

    footer class: "colophon" do
      text Copy::FOOTER
    end

    # Everything the console script needs to resume a session without
    # another round trip: the lesson list with prompts, and the handful of
    # client-rendered strings. Lesson checks are NOT in here; what counts as
    # passing is decided server side, in the response, every time.
    #
    # The gsub closes the one hole a JSON-in-script island has: a string
    # containing "</" would otherwise end the script tag early. The escaped
    # slash parses back to the same JSON.
    tag "script", id: "trycrystal-console", type: "application/json" do
      raw console_boot_json
    end
  end

  private def line(kind : String, text : String)
    tag "div", class: "line line--#{kind}" do
      text text
    end
  end

  private def console_boot_json : String
    {
      lessons: Lessons::ALL.map(&.public_payload),
      copy:    {
        welcome:      Copy::WELCOME,
        welcome_back: Copy::WELCOME_BACK,
        finale:       Copy::FINALE,
        value_label:  Copy::VALUE_LABEL,
        progress:     Copy::PROGRESS_TEMPLATE,
        empty:        Copy::EMPTY_SUBMISSION,
        unreachable:  Copy::RUNNER_UNREACHABLE_BROWSER,
      },
    }.to_json.gsub("</", "<\\/")
  end
end
