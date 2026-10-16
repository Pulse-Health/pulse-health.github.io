# Pulse website

Static implementation of the Claude Design canvas **Pulse Webseite** (start page, mobile, mobile menu, logo and favicon):
https://claude.ai/artifact/JW4ChXCCJdWKjsZBVJwts5

Plain HTML, CSS and a little JavaScript. No build step, no external requests (Open Sans is self-hosted, so no visitor data goes
to a font CDN).

```
website/
  index.html      the page (German)
  style.css       all styles; colours are CSS variables at the top
  app.js          mobile menu and the optional hero intro
  assets/         hero.jpg (still from the design), favicon.svg / .png, apple-touch-icon.png
  fonts/          Open Sans 300/400/600/700 (latin), SIL OFL 1.1 (OFL.txt)
```

Preview locally: `python3 -m http.server` in the repository root, then open `/website/`. The links to the legal pages
(`/impressum.html`, `/datenschutz.html`, `/agb.html`) are root-absolute, so they only resolve when served from the site root.

## Colours

The design has two palettes. **Lavendel** is the default. The previous green palette ("alte Farben") is one attribute away:

```html
<html lang="de" data-theme="gruen">
```

Every colour lives in the variables at the top of `style.css`; nothing else changes between the two.

## Hero film and intro

The design describes a hero **film** that plays alone for 2 seconds, then darkens, fades in "Pulse" and the line below, then the
rest of the text, and finally slides the navigation in. Anyone who scrolls earlier gets everything at once and the film stops.

The design only contains one still frame (`assets/hero.jpg`), so the page currently shows the still and everything is visible
immediately. The sequence is already built. To switch it on once there is a film:

1. Put the film at `assets/hero.mp4` (and ideally a `.webm`).
2. In `index.html`, add `data-intro` to `<header class="hero">` and add, directly after the `<img class="hero__img">`:

   ```html
   <video class="hero__img hero__film" src="assets/hero.mp4" poster="assets/hero.jpg" autoplay muted loop playsinline></video>
   ```

   (Keep the `<img>` as a fallback, or remove it if the video is enough.)

The intro is skipped for `prefers-reduced-motion` and when JavaScript is off.

## Deliberately left out

- **Anmelden (sign-in) and "Zur Konsole".** The design has a sign-in page and links to it, but there is no console or login backend
  in this repository. A form that collects an e-mail address and does nothing would be misleading, so the nav button, the sign-in
  page and the "Zur Konsole" button are not built. The text of the "Für Fachleute" section is unchanged. Add them once the console exists.
- **English version.** The design is German only.

## Putting it live

This folder is self-contained, so it can be served from `/website/` as it is. To make it the home page, move the contents of
`website/` into the repository root. That replaces the current `index.html` (the legal-pages hub), so decide first what should
happen to that page and to `index-en.html`, which links back to it.
