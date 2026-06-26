// ---------------------------------------------------------------------------
// Pulse — site-wide configuration
//
// Single source of truth for shared contact details. Change the address here
// once and every page updates automatically.
//
// Usage in HTML:
//   - Plain text:   <span class="js-contact-email"></span>
//   - Mailto link:  <a class="js-contact-email-link"></a>
//                   (the href and the link text are filled in automatically)
//
// For legally required pages (Impressum, Datenschutz/Privacy, AGB/Terms) always
// add a <noscript> fallback next to the placeholder so the address is still
// reachable when JavaScript is disabled.
// ---------------------------------------------------------------------------

window.PULSE_SITE = window.PULSE_SITE || {};
window.PULSE_SITE.contactEmail = "robin.juengerich@icloud.com";

(function () {
  "use strict";

  function applyContactEmail() {
    var email = window.PULSE_SITE.contactEmail;
    if (!email) return;

    // Plain-text placeholders.
    document.querySelectorAll(".js-contact-email").forEach(function (el) {
      el.textContent = email;
    });

    // mailto: links — fill href, and use the address as label when empty.
    document.querySelectorAll("a.js-contact-email-link").forEach(function (el) {
      var subject = el.getAttribute("data-subject");
      var href = "mailto:" + email;
      if (subject) {
        href += "?subject=" + encodeURIComponent(subject);
      }
      el.setAttribute("href", href);
      if (!el.textContent.trim()) {
        el.textContent = email;
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", applyContactEmail);
  } else {
    applyContactEmail();
  }
})();
