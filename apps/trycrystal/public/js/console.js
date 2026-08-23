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
  var counter = document.getElementById("counter");
  var progress = document.getElementById("progress");

  if (!bootEl || !form || !transcript || !input) {
    return;
  }

  var boot = JSON.parse(bootEl.textContent);
  var lessons = boot.lessons;
  var copy = boot.copy;

  var PROGRESS_KEY = "trycrystal.progress";
  var HISTORY_KEY = "trycrystal.history";
  var HISTORY_LIMIT = 100;

  var lessonIndex = 0;
  var history = [];
  var historyCursor = null;
  var draft = "";
  var submissions = 0;
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

  function scrollToEnd() {
    transcript.scrollTop = transcript.scrollHeight;
  }

  function currentLesson() {
    return lessons[lessonIndex];
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

  // The counter names the line about to be typed, the way a REPL numbers
  // its prompt, so it reads one ahead of the submissions already sent.
  function nextCounter() {
    submissions += 1;
    var padded = String(submissions + 1);
    while (padded.length < 3) {
      padded = "0" + padded;
    }
    return padded + ">";
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
      line("lesson", lessons[index].prompt);
    }
    if (index === lessons.length) {
      // Finished the tutorial on a previous visit: welcome them back as
      // finished rather than dropping them into a prompt they already beat.
      while (transcript.firstChild) {
        transcript.removeChild(transcript.firstChild);
      }
      line("system", copy.welcome_back);
      line("final", copy.finale);
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

    history.push(code);
    if (history.length > HISTORY_LIMIT) {
      history = history.slice(-HISTORY_LIMIT);
    }
    writeJSON(HISTORY_KEY, history);
    historyCursor = null;
    draft = "";

    line("echo", code);
    counter.textContent = nextCounter();
    input.value = "";
    autosize();

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
      line("out", body.stdout);
    }
    if (body.stderr) {
      line("err", body.stderr);
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
      } else if (body.lesson.next) {
        lessonIndex = lessons.findIndex(function (lesson) {
          return lesson.id === body.lesson.next.id;
        });
        if (lessonIndex < 0) {
          lessonIndex = 0;
        }
        writeJSON(PROGRESS_KEY, body.lesson.next.id);
        line("lesson", body.lesson.next.prompt);
      }
      renderProgress();
    }
  }

  // ---- keyboard ------------------------------------------------------------

  function autosize() {
    input.style.height = "auto";
    input.style.height = Math.min(input.scrollHeight, 192) + "px";
  }

  input.addEventListener("input", autosize);

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    submit(input.value);
  });

  input.addEventListener("keydown", function (event) {
    // Enter submits; Shift+Enter makes a newline, for a submission that
    // grew past one line.
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      submit(input.value);
      return;
    }

    // Up walks back through history when the caret sits at the very start,
    // Down walks forward when it sits at the very end, so a multiline draft
    // can still be edited with the arrow keys mid-text.
    if (event.key === "ArrowUp" && input.selectionStart === 0 && input.selectionEnd === 0) {
      if (history.length === 0) {
        return;
      }
      event.preventDefault();
      if (historyCursor === null) {
        draft = input.value;
        historyCursor = history.length - 1;
      } else {
        historyCursor = Math.max(0, historyCursor - 1);
      }
      input.value = history[historyCursor];
      input.setSelectionRange(input.value.length, input.value.length);
      autosize();
      return;
    }

    if (event.key === "ArrowDown" && input.selectionStart === input.value.length) {
      if (historyCursor === null) {
        return;
      }
      event.preventDefault();
      historyCursor += 1;
      if (historyCursor >= history.length) {
        historyCursor = null;
        input.value = draft;
      } else {
        input.value = history[historyCursor];
      }
      input.setSelectionRange(input.value.length, input.value.length);
      autosize();
      return;
    }

    // Escape empties the line without submitting it.
    if (event.key === "Escape") {
      input.value = "";
      historyCursor = null;
      autosize();
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

  // ---- go -------------------------------------------------------------------

  history = readJSON(HISTORY_KEY, []);
  if (!Array.isArray(history)) {
    history = [];
  }
  resume();
  renderProgress();
  autosize();
  input.focus();
})();
