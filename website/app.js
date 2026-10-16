// Pulse website: mobile menu and the optional hero intro. The page is fully usable without this file.
(function () {
  "use strict";

  var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---- mobile menu ---------------------------------------------------------
  var toggle = document.querySelector(".nav__toggle");
  var links = document.getElementById("nav-links");

  if (toggle && links) {
    var setOpen = function (open) {
      links.classList.toggle("is-open", open);
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      toggle.setAttribute("aria-label", open ? "Menü schließen" : "Menü öffnen");
    };

    toggle.addEventListener("click", function () {
      setOpen(toggle.getAttribute("aria-expanded") !== "true");
    });
    links.addEventListener("click", function (e) {
      if (e.target.closest("a")) setOpen(false);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
        setOpen(false);
        toggle.focus();
      }
    });
  }

  // ---- hero intro ----------------------------------------------------------
  // Runs only when the hero carries data-intro. 0-2 s: the film plays alone. Then the shade (s1),
  // the logo and title (s2), the rest of the text (s3) and the navigation (s4) come in one after
  // another. Anyone who scrolls, taps or presses a key earlier gets everything at once and the film stops.
  var hero = document.querySelector(".hero[data-intro]");
  if (!hero) return;

  var film = hero.querySelector(".hero__film");
  var steps = [["s1", 2000], ["s2", 2600], ["s3", 3300], ["s4", 4000]];
  var timers = [];

  function finish() {
    timers.forEach(clearTimeout);
    steps.forEach(function (s) { hero.classList.add(s[0]); });
    if (film && typeof film.pause === "function") film.pause();
    ["scroll", "wheel", "touchstart", "keydown", "pointerdown"].forEach(function (name) {
      window.removeEventListener(name, finish);
    });
  }

  if (reduced) {
    finish();
    return;
  }

  steps.forEach(function (s) {
    timers.push(setTimeout(function () { hero.classList.add(s[0]); }, s[1]));
  });
  ["scroll", "wheel", "touchstart", "keydown", "pointerdown"].forEach(function (name) {
    window.addEventListener(name, finish, { passive: true });
  });
})();
