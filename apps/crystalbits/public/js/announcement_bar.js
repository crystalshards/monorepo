// Dismiss control for the announcement bar.
//
// The bar itself needs none of this: it renders in the layout, links to the
// announcement, and stays. This file adds one thing on top, a dismiss button
// that remembers the choice, and adds nothing else. If it never loads, the
// bar is a complete, working element with no button on it, because the
// button arrives with the hidden attribute and only this script removes it.
//
// The choice is remembered per announcement slug, so dismissing one launch
// announcement does not suppress whatever the bar points at next.
(function () {
  "use strict";

  var bar = document.querySelector("[data-announcement-bar]");
  if (!bar) {
    return;
  }

  var slug = bar.getAttribute("data-announcement-slug") || "";
  var key = "announcement-bar-dismissed";

  // localStorage can throw, in a private window or where storage is refused.
  // That reader gets the button working for the page they are on and the bar
  // back on the next one, which is the honest failure mode for a preference
  // there is nowhere to keep.
  function remembered() {
    try {
      return window.localStorage.getItem(key) === slug;
    } catch (e) {
      return false;
    }
  }

  function remember() {
    try {
      window.localStorage.setItem(key, slug);
    } catch (e) {
      // See remembered(): forgetfulness is the failure mode, not an error.
    }
  }

  if (remembered()) {
    bar.parentNode.removeChild(bar);
    return;
  }

  var button = bar.querySelector("[data-announcement-dismiss]");
  if (!button) {
    return;
  }

  button.removeAttribute("hidden");
  button.addEventListener("click", function () {
    bar.parentNode.removeChild(bar);
    remember();
  });
})();
