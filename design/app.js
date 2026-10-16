// Scroll-reveal for the landing page. Content is fully visible without JavaScript:
// the "js" class (which enables the hidden starting state) is only added when this script runs.
(function () {
  "use strict";

  var root = document.documentElement;
  var items = document.querySelectorAll(".reveal");
  var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (!items.length || reduced || !("IntersectionObserver" in window)) return;

  root.classList.add("js");

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add("in");
        io.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });

  items.forEach(function (el) { io.observe(el); });
})();
