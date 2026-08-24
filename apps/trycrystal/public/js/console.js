// The console. Everything on the page is already structure: the transcript
// has the welcome and lesson one's prompt in it, server rendered, and this
// script's whole job is the round trips: read a submission, send it to
// /api/executions, and append what came back.
//
// ONE RULE ABOVE ALL OTHERS: nothing that came over the wire, and nothing
// the visitor typed, is ever inserted as HTML. Every string lands through
// textContent, on this side, and as escaped text on the server side. The
// product executes whatever a visitor types, so treating any of it as
// markup is not a styling bug, it is the hole.
//
// A second rule keeps the voice in one place: this script renders strings
// but authors none of them. Every sentence it can ever print arrives in the
// boot JSON under "copy", from src/copy.cr.
(function () {
  "use strict";

  var bootEl = document.getElementById("trycrystal-console");
  var form = document.getElementById("console-form");
  var transcript = document.getElementById("transcript");
  var input = document.getElementById("console-input");
  var progress = document.getElementById("progress");
  var lessonPane = document.getElementById("lesson-pane");
  var copyButton = document.getElementById("copy-example");

  if (!bootEl || !form || !transcript || !input || !lessonPane) {
    return;
  }

  var boot = JSON.parse(bootEl.textContent);
  var lessons = boot.lessons;
  var copy = boot.copy;

  var PROGRESS_KEY = "trycrystal.progress";

  var lessonIndex = 0;
  var pending = false;

  // ---- storage ------------------------------------------------------------
  // localStorage can throw, in a private window or where storage is refused.
  // That reader gets a console that works for this page and forgets on the
  // next one, which is the honest failure mode for progress there is nowhere
  // else to keep. See announcement_bar.js in crystalgigs for the precedent.

  function readJSON(key, fallback) {
    try {
      var raw = window.localStorage.getItem(key);
      return raw === null ? fallback : JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  }

  function writeJSON(key, value) {
    try {
      window.localStorage.setItem(key, JSON.stringify(value));
    } catch (e) {
      // Forgetting is the failure mode, not an error.
    }
  }

  // ---- rendering ----------------------------------------------------------

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) {
      node.className = className;
    }
    if (text !== undefined && text !== null) {
      node.textContent = text;
    }
    return node;
  }

  function line(kind, text) {
    var node = el("div", "line line--" + kind, text);
    transcript.appendChild(node);
    scrollToEnd();
    return node;
  }

  // A line built from ANSI segments, each a span carrying the classes the
  // server derived from the compiler's escape sequences.
  //
  // Same rule as everywhere else: every string lands through textContent, and
  // the class names come from a closed set the server composes, so compiler
  // output cannot invent a class or a tag. If segments are missing for any
  // reason the caller falls back to the plain string, so text is never lost
  // to a parsing problem.
  function segmentLine(kind, segments) {
    var node = el("div", "line line--" + kind);
    for (var i = 0; i < segments.length; i += 1) {
      var seg = segments[i];
      node.appendChild(el("span", seg.classes || null, seg.text));
    }
    transcript.appendChild(node);
    scrollToEnd();
    return node;
  }

  // Renders whichever the server gave us. Segments win when present and
  // non-empty; the raw string is the fallback.
  function streamLine(kind, raw, segments) {
    if (segments && segments.length) {
      return segmentLine(kind, segments);
    }
    return line(kind, raw);
  }

  function scrollToEnd() {
    transcript.scrollTop = transcript.scrollHeight;
  }

  function currentLesson() {
    return lessons[lessonIndex];
  }

  // The lesson pane, rebuilt for one lesson.
  //
  // Same rule as the transcript: every string lands through textContent, and
  // no markup is built from anything that came over the wire. The pane is
  // cleared and rebuilt rather than patched, because a half-updated lesson
  // (new narrative, previous sample) is a worse failure than a flicker.
  function renderLesson(lesson) {
    while (lessonPane.firstChild) {
      lessonPane.removeChild(lessonPane.firstChild);
    }

    if (!lesson) {
      // Past the last lesson the pane says so rather than sitting on a
      // prompt the visitor already beat.
      lessonPane.appendChild(el("p", "lesson-text", copy.finale));
      return;
    }

    lessonPane.appendChild(el("p", "lesson-text", lesson.prompt));

    if (lesson.code_sample) {
      var example = el("div", "example");
      example.appendChild(el("span", "example-label", copy.example_label));

      var pre = el("pre", "example-code");
      pre.appendChild(el("code", null, lesson.code_sample));
      example.appendChild(pre);

      var button = el("button", "ghost", copy.copy_button);
      button.type = "button";
      button.addEventListener("click", function () {
        copyExample(lesson.code_sample);
      });
      example.appendChild(button);

      lessonPane.appendChild(example);
    }

    if (lesson.hint) {
      var hint = el("p", "lesson-hint");
      hint.appendChild(el("span", "hint-label", copy.hint_label));
      hint.appendChild(document.createTextNode(" " + lesson.hint));
      lessonPane.appendChild(hint);
    }
  }

  // Loads the lesson's line into the editor and puts the caret at the end,
  // so the next thing the visitor does is press Run or edit it.
  function copyExample(sample) {
    input.value = sample;
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
  }

  function renderProgress() {
    if (!progress) {
      return;
    }
    var label = progress.querySelector(".progress-label");
    if (label) {
      label.textContent = copy.progress
        .replace("{n}", String(Math.min(lessonIndex + 1, lessons.length)))
        .replace("{total}", String(lessons.length));
    }
    var steps = progress.querySelectorAll(".step");
    for (var i = 0; i < steps.length; i += 1) {
      steps[i].className = "step";
      if (i < lessonIndex) {
        steps[i].className = "step step--done";
      } else if (i === lessonIndex) {
        steps[i].className = "step step--current";
      }
    }
  }

  // ---- resuming -----------------------------------------------------------
  // The server renders lesson one for everyone, because it cannot read
  // localStorage. A visitor partway through gets the transcript rebuilt
  // around their actual lesson the moment this script runs.

  function resume() {
    var savedId = readJSON(PROGRESS_KEY, null);
    if (!savedId) {
      return;
    }
    var index = -1;
    for (var i = 0; i < lessons.length; i += 1) {
      if (lessons[i].id === savedId) {
        index = i;
        break;
      }
    }
    if (index > 0) {
      lessonIndex = index;
      while (transcript.firstChild) {
        transcript.removeChild(transcript.firstChild);
      }
      line("system", copy.welcome_back);
      renderLesson(lessons[index]);
    }
    if (savedId === "done") {
      // Finished the tutorial on a previous visit: the lesson pane says so
      // rather than dropping them into a prompt they already beat.
      lessonIndex = lessons.length;
      while (transcript.firstChild) {
        transcript.removeChild(transcript.firstChild);
      }
      line("system", copy.welcome_back);
      renderLesson(null);
    }
  }

  // ---- a round trip -------------------------------------------------------

  function submit(code) {
    if (pending) {
      return;
    }
    if (!code.trim()) {
      line("system", copy.empty);
      return;
    }

    // The editor KEEPS the submission. In a transcript console the line is
    // consumed because the transcript is the record; in an editor the code is
    // the thing you are working on, and clearing it after every Run would
    // throw away the draft a visitor is iterating on.
    line("echo", code);

    pending = true;
    form.setAttribute("data-pending", "pending");
    input.disabled = true;
    scrollToEnd();

    // After the last lesson there is no current lesson, and the console
    // stays open as a plain REPL: no lesson id goes up, no verdict comes
    // back. Sending a stale id here, or reading .id off nothing, is what
    // wedges a finished console.
    var lesson = currentLesson();

    fetch("/api/executions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        code: code,
        lesson_id: lesson ? lesson.id : null,
      }),
    })
      .then(function (response) {
        return response.json().then(function (body) {
          return { ok: response.ok, body: body };
        });
      })
      .catch(function () {
        return { ok: false, body: { message: copy.unreachable } };
      })
      .then(function (outcome) {
        arrived(outcome);
      });
  }

  function arrived(outcome) {
    pending = false;
    form.removeAttribute("data-pending");
    input.disabled = false;
    input.focus();

    if (!outcome.ok) {
      line("system", outcome.body && outcome.body.message ? outcome.body.message : copy.unreachable);
      return;
    }

    var body = outcome.body;

    if (body.stdout) {
      streamLine("out", body.stdout, body.stdout_segments);
    }
    if (body.stderr) {
      streamLine("err", body.stderr, body.stderr_segments);
    }
    if (body.value !== null && body.value !== undefined) {
      line("value", copy.value_label + " " + body.value);
    }
    if (typeof body.duration_ms === "number") {
      line("meta", body.duration_ms + " ms");
    }
    if (body.lesson && body.lesson.reaction) {
      line("reaction", body.lesson.reaction);
    }

    if (body.lesson && body.lesson.advanced) {
      if (body.lesson.finished) {
        lessonIndex = lessons.length;
        writeJSON(PROGRESS_KEY, "done");
        line("final", copy.finale);
        renderLesson(null);
      } else if (body.lesson.next) {
        lessonIndex = lessons.findIndex(function (lesson) {
          return lesson.id === body.lesson.next.id;
        });
        if (lessonIndex < 0) {
          lessonIndex = 0;
        }
        writeJSON(PROGRESS_KEY, body.lesson.next.id);
        renderLesson(lessons[lessonIndex] || body.lesson.next);
      }
      renderProgress();
    }
  }

  // ---- keyboard ------------------------------------------------------------

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    submit(input.value);
  });

  input.addEventListener("keydown", function (event) {
    // This is an editor, so Enter belongs to the text. Running is a key you
    // have to mean: Cmd+Enter on a Mac, Ctrl+Enter elsewhere, which is what
    // every editor with a run button already trains people to press. The old
    // single-line console submitted on Enter, and keeping that here would
    // make writing a two-line program impossible.
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      submit(input.value);
      return;
    }

    // Tab indents instead of leaving the editor. Shift+Tab still escapes, so
    // the pane is not a keyboard trap, which would fail WCAG 2.1.2.
    if (event.key === "Tab" && !event.shiftKey) {
      event.preventDefault();
      var start = input.selectionStart;
      var end = input.selectionEnd;
      input.value = input.value.slice(0, start) + "  " + input.value.slice(end);
      input.setSelectionRange(start + 2, start + 2);
    }
  });

  // Clicking anywhere in the transcript that is not a link goes home to the
  // input, because the console is the whole page and the keyboard is the
  // point.
  transcript.addEventListener("click", function (event) {
    if (event.target === transcript) {
      input.focus();
    }
  });

  if (copyButton) {
    copyButton.addEventListener("click", function () {
      var lesson = currentLesson();
      if (lesson && lesson.code_sample) {
        copyExample(lesson.code_sample);
      }
    });
  }

  // ---- go -------------------------------------------------------------------

  resume();
  renderProgress();
  input.focus();
})();
