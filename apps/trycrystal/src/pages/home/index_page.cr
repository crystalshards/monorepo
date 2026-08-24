# The whole product is this page, laid out as a workspace rather than a
# column: a compact masthead, the lesson on the left, and the editor over its
# output on the right. It fills the viewport, because the person reading it
# has a developer's screen and a tutorial that wastes it feels like a
# brochure rather than a tool.
#
# The shape is the one try.ruby-lang.org settled on, for the same reason:
# reading the lesson and writing the code are two things you do at once, so
# they get two panes rather than taking turns in one scroll.
#
# Three rules hold the page together:
#
#   Everything a visitor's code produced, or a visitor typed, moves as JSON
#   and is rendered with textContent. Nothing in this page or in console.js
#   builds markup from it, so it can never become HTML.
#
#   Every word the page says comes from Copy. This file is structure only.
#
#   The lesson pane and the output pane are separate surfaces. Narrative goes
#   left and never scrolls away under execution output; results go right and
#   never push the lesson off screen.
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

    tag "main", class: "workspace", id: "workspace" do
      lesson_pane
      workbench
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

  # The left pane. Server rendered for lesson one so a visitor reads a real
  # lesson before any script runs; console.js replaces its contents as the
  # lessons advance.
  private def lesson_pane
    tag "section", class: "pane pane--lesson", "aria-label": Copy::LESSON_PANE_LABEL do
      tag "div", class: "pane-head" do
        span Copy::LESSON_PANE_LABEL, class: "pane-title"
      end

      tag "div", class: "pane-body", id: "lesson-pane" do
        first = Lessons.first

        para Copy.prompt(first, 1, Lessons.total), class: "lesson-text"

        tag "div", class: "example" do
          span Copy::EXAMPLE_LABEL, class: "example-label"
          tag "pre", class: "example-code", id: "lesson-sample" do
            code first.code_sample
          end
          tag "button", type: "button", class: "ghost", id: "copy-example" do
            text Copy::COPY_BUTTON
          end
        end

        para class: "lesson-hint", id: "lesson-hint" do
          span Copy::HINT_LABEL, class: "hint-label"
          text " "
          text first.hint
        end
      end
    end
  end

  # The right pane: what you write, over what came back.
  private def workbench
    tag "div", class: "workbench" do
      tag "form", class: "pane pane--editor", id: "console-form" do
        tag "div", class: "pane-head" do
          span Copy::EDITOR_PANE_LABEL, class: "pane-title"
          span Copy::RUN_HINT, class: "pane-hint"
          tag "button", type: "submit", class: "run", id: "run" do
            text Copy::RUN_BUTTON
          end
        end

        label Copy::INPUT_LABEL, for: "console-input", class: "visually-hidden"
        textarea "", id: "console-input", class: "input",
          spellcheck: "false", autocapitalize: "off", autocomplete: "off",
          wrap: "off", autofocus: "autofocus"
      end

      tag "section", class: "pane pane--output", "aria-label": Copy::OUTPUT_PANE_LABEL do
        tag "div", class: "pane-head" do
          span Copy::OUTPUT_PANE_LABEL, class: "pane-title"
        end

        tag "div", class: "pane-body transcript", id: "transcript",
          role: "log", "aria-live": "polite" do
          line "system", Copy::WELCOME
        end

        noscript do
          text Copy::NOSCRIPT
        end
      end
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
        welcome:       Copy::WELCOME,
        welcome_back:  Copy::WELCOME_BACK,
        finale:        Copy::FINALE,
        value_label:   Copy::VALUE_LABEL,
        progress:      Copy::PROGRESS_TEMPLATE,
        empty:         Copy::EMPTY_SUBMISSION,
        unreachable:   Copy::RUNNER_UNREACHABLE_BROWSER,
        example_label: Copy::EXAMPLE_LABEL,
        copy_button:   Copy::COPY_BUTTON,
        hint_label:    Copy::HINT_LABEL,
      },
    }.to_json.gsub("</", "<\\/")
  end
end
