// Filter for the docs sidebar tree.
//
// The tree itself is <details>/<summary> and needs none of this: it expands,
// collapses, takes the keyboard and reports its state without a line of
// script, and the branch holding the current type is already open because the
// server rendered it open. This file adds one thing on top, the filter field,
// and adds nothing else. If it never loads, the sidebar is a complete,
// working, fully navigable tree with a search box that does nothing.
//
// Rows carry the qualified name in data-name, so typing a namespace or a leaf
// both find the row. A match reveals itself and every ancestor on the way up,
// unfolding the branches it passes through, which is how a hit inside a
// collapsed namespace becomes visible instead of silently not being there.
(function () {
  "use strict";

  var input = document.querySelector("[data-docs-filter]");
  var tree = document.querySelector("[data-docs-nav-tree]");
  if (!input || !tree) {
    return;
  }

  var items = Array.prototype.slice.call(tree.querySelectorAll(".docs-nav-item"));
  var branches = Array.prototype.slice.call(tree.querySelectorAll(".docs-nav-branch"));
  var status = document.querySelector("[data-docs-filter-status]");
  var announceTimer = null;

  // Which branches the server decided to open. Clearing the filter restores
  // that, rather than collapsing the reader out of their own position.
  var serverOpen = branches.map(function (branch) {
    return branch.open;
  });

  // A live region repeated on every keystroke is noise, so the count lands
  // once the typing stops.
  function announce(message) {
    if (!status) {
      return;
    }

    if (announceTimer) {
      window.clearTimeout(announceTimer);
    }

    announceTimer = window.setTimeout(function () {
      status.textContent = message;
    }, 300);
  }

  // Walk from the matched row up to the tree root, showing each ancestor row
  // and opening each branch in between. The row's own branch is untouched: it
  // opens only if something inside it matched too.
  function reveal(item) {
    var node = item;

    while (node && node !== tree) {
      if (node.nodeType === 1) {
        if (node.classList.contains("docs-nav-item")) {
          node.hidden = false;
        }

        if (node.tagName === "DETAILS") {
          node.open = true;
        }
      }

      node = node.parentNode;
    }
  }

  function restore() {
    items.forEach(function (item) {
      item.hidden = false;
    });

    branches.forEach(function (branch, index) {
      branch.open = serverOpen[index];
    });

    announce("");
  }

  function filter(query) {
    var matches = 0;

    items.forEach(function (item) {
      item.hidden = true;
    });

    items.forEach(function (item) {
      var name = item.getAttribute("data-name") || "";

      if (name.indexOf(query) === -1) {
        return;
      }

      matches += 1;
      reveal(item);
    });

    if (matches === 0) {
      announce("No types match " + query);
    } else if (matches === 1) {
      announce("1 type matches " + query);
    } else {
      announce(matches + " types match " + query);
    }
  }

  input.addEventListener("input", function () {
    var query = input.value.trim().toLowerCase();

    if (query === "") {
      restore();
    } else {
      filter(query);
    }
  });
})();
