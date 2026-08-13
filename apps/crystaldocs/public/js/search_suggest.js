// Suggestions for the masthead search field.
//
// The field is a plain GET form and stays one. Everything below is added to a
// form that already works: if this file never loads, never parses, or the
// endpoint is down, the reader types and presses Enter and gets the search
// results page, which is exactly what happened before there was a script here.
// Nothing in the server-rendered markup claims otherwise, which is why the
// combobox roles are attached here rather than rendered: an input that
// announces itself as a combobox and never produces a popup is a lie told to
// a screen reader.
//
// The pattern is ARIA's combobox with a listbox popup. Focus never leaves the
// input; the active option is pointed at with aria-activedescendant, so typing
// keeps working while the arrow keys walk the list. Options carry no links,
// because role="option" may not contain interactive content; the row's target
// is on a data attribute and this navigates to it.
(function () {
  "use strict";

  // Long enough that a keystroke does not become a request, short enough that
  // the list is there by the time the reader has stopped typing.
  var INPUT_DELAY = 150;

  // The count lands after the typing stops, for the reason the docs sidebar
  // filter gives: a live region read out on every keystroke is noise.
  var ANNOUNCE_DELAY = 300;

  function upgrade(input) {
    var endpoint = input.getAttribute("data-search-suggest");
    var listbox = document.getElementById(
      input.getAttribute("data-search-suggest-listbox") || ""
    );
    if (!endpoint || !listbox) {
      return;
    }

    var form = input.form;
    var status = form
      ? form.querySelector("[data-search-suggest-status]")
      : null;
    var noun = input.getAttribute("data-search-suggest-noun") || "result";
    var minimum = parseInt(input.getAttribute("data-search-suggest-min"), 10);
    if (isNaN(minimum) || minimum < 1) {
      minimum = 2;
    }

    var options = [];
    var activeIndex = -1;
    var inputTimer = null;
    var announceTimer = null;
    // Responses can arrive out of order. Only the newest request is allowed to
    // paint, or a slow answer for "ke" overwrites the list for "kemal".
    var latestRequest = 0;

    // The roles go on now, once there is a script to honour them.
    input.setAttribute("role", "combobox");
    input.setAttribute("aria-expanded", "false");
    input.setAttribute("aria-controls", listbox.id);
    input.setAttribute("aria-autocomplete", "list");
    input.setAttribute("aria-haspopup", "listbox");
    // The browser's own history dropdown would cover this one. Set here so a
    // reader without script keeps it.
    input.setAttribute("autocomplete", "off");

    function announce(message) {
      if (!status) {
        return;
      }

      if (announceTimer) {
        window.clearTimeout(announceTimer);
      }

      announceTimer = window.setTimeout(function () {
        status.textContent = message;
      }, ANNOUNCE_DELAY);
    }

    function countMessage(total) {
      if (total === 0) {
        return "No " + noun + " suggestions.";
      }

      if (total === 1) {
        return "1 " + noun + " suggestion. Use the arrow keys to review it.";
      }

      return (
        total + " " + noun + " suggestions. Use the arrow keys to review them."
      );
    }

    function setActive(index) {
      if (activeIndex >= 0 && options[activeIndex]) {
        options[activeIndex].setAttribute("aria-selected", "false");
        options[activeIndex].classList.remove("is-active");
      }

      activeIndex = index;

      if (index < 0 || !options[index]) {
        input.removeAttribute("aria-activedescendant");
        return;
      }

      var option = options[index];
      option.setAttribute("aria-selected", "true");
      option.classList.add("is-active");
      input.setAttribute("aria-activedescendant", option.id);

      // Only moves when the row is out of view, so arrowing through a short
      // list does not scroll the page.
      if (option.scrollIntoView) {
        option.scrollIntoView({ block: "nearest" });
      }
    }

    function close() {
      setActive(-1);
      listbox.hidden = true;
      input.setAttribute("aria-expanded", "false");
    }

    function clear() {
      close();
      options = [];
      listbox.textContent = "";
    }

    function open() {
      if (options.length === 0) {
        close();
        return;
      }

      listbox.hidden = false;
      input.setAttribute("aria-expanded", "true");
    }

    function row(suggestion, index) {
      var option = document.createElement("li");
      option.id = listbox.id + "-option-" + index;
      option.className = "search-suggestion";
      option.setAttribute("role", "option");
      option.setAttribute("aria-selected", "false");
      option.setAttribute("data-path", suggestion.path);

      var name = document.createElement("span");
      name.className = "search-suggestion-name";
      name.textContent = suggestion.name;
      option.appendChild(name);

      // The repository, when it says something the name does not. Two
      // repositories can publish under one name, so without it the list can
      // show the same word twice with no way to tell them apart. Null for a
      // package with no repository identity at all, which is what the
      // standard library and the legacy rows are.
      if (suggestion.repository && suggestion.repository !== suggestion.name) {
        var slug = document.createElement("span");
        slug.className = "search-suggestion-slug";
        slug.textContent = suggestion.repository;
        option.appendChild(slug);
      }

      return option;
    }

    function render(suggestions) {
      var list = document.createDocumentFragment();

      options = suggestions.map(function (suggestion, index) {
        var option = row(suggestion, index);
        list.appendChild(option);
        return option;
      });

      setActive(-1);
      listbox.textContent = "";
      listbox.appendChild(list);

      open();
      announce(countMessage(options.length));
    }

    function request(term) {
      var sequence = ++latestRequest;

      window
        .fetch(endpoint + "?query=" + encodeURIComponent(term), {
          headers: { Accept: "application/json" },
          credentials: "same-origin",
        })
        .then(function (response) {
          if (!response.ok) {
            throw new Error("suggestions unavailable");
          }
          return response.json();
        })
        .then(function (body) {
          if (sequence !== latestRequest) {
            return;
          }

          render(body.suggestions || []);
        })
        .catch(function () {
          if (sequence !== latestRequest) {
            return;
          }

          // Silent. The reader still has a working search form and telling
          // them a background request failed helps nobody.
          clear();
        });
    }

    function navigate(index) {
      var option = options[index];
      if (!option) {
        return;
      }

      window.location.assign(option.getAttribute("data-path"));
    }

    input.addEventListener("input", function () {
      if (inputTimer) {
        window.clearTimeout(inputTimer);
      }

      var term = input.value.trim();

      if (term.length < minimum) {
        // Nothing to ask about, and nothing on screen should survive it. The
        // sequence bump cancels any answer still in flight.
        latestRequest += 1;
        clear();
        announce("");
        return;
      }

      inputTimer = window.setTimeout(function () {
        request(term);
      }, INPUT_DELAY);
    });

    input.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        if (!listbox.hidden) {
          // Dismiss the list and keep what was typed. The form is still there
          // to submit.
          event.preventDefault();
          close();
        }
        return;
      }

      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        if (options.length === 0) {
          return;
        }

        event.preventDefault();

        if (listbox.hidden) {
          open();
        }

        var step = event.key === "ArrowDown" ? 1 : -1;
        var next = activeIndex + step;

        // Wraps, so the list is a loop rather than a dead end at each end.
        if (next >= options.length) {
          next = 0;
        } else if (next < 0) {
          next = options.length - 1;
        }

        setActive(next);
        return;
      }

      if (event.key === "Enter") {
        if (!listbox.hidden && activeIndex >= 0) {
          // A chosen suggestion goes straight to that package. With nothing
          // chosen this does nothing and the form submits the search, which
          // is what Enter has always done here.
          event.preventDefault();
          navigate(activeIndex);
        }
        return;
      }

      if (event.key === "Tab") {
        close();
      }
    });

    // mousedown, not click: the default would blur the input first, the blur
    // handler would hide the list, and the click would land on nothing.
    listbox.addEventListener("mousedown", function (event) {
      event.preventDefault();
    });

    listbox.addEventListener("click", function (event) {
      var option = event.target.closest("[role='option']");
      if (!option) {
        return;
      }

      window.location.assign(option.getAttribute("data-path"));
    });

    input.addEventListener("blur", function () {
      close();
    });
  }

  // Every field on the page, so a second search bar outside the masthead gets
  // the same behaviour without any wiring.
  Array.prototype.slice
    .call(document.querySelectorAll("[data-search-suggest]"))
    .forEach(upgrade);
})();
