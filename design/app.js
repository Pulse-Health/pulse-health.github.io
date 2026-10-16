/* ==========================================================================
   Rebase · onboarding & login prototype
   --------------------------------------------------------------------------
   Design prototype only: no network requests, nothing is stored. What you type
   into the form stays in the page and is gone on reload.

   Deep links:  index.html#welcome | #signup | #login | #goal | #health | #notify | #done
                index.html?lang=de   (otherwise the browser language decides)
   ========================================================================== */
(function () {
    'use strict';

    /* ----------------------------------------------------------------------
       Copy. Every key exists in both languages; German uses the informal "du"
       like the plain-language privacy summary (datenschutz-einfach.html).
       ---------------------------------------------------------------------- */
    var STRINGS = {
        en: {
            'doc.title': 'Rebase – Onboarding & Login (design prototype)',
            'video.pause': 'Pause background video',
            'video.play': 'Play background video',

            'welcome.h1': 'Welcome to Rebase',
            'pager.label': 'Rebase highlights',
            'pager.go': 'Show highlight {n} of {total}',
            'slide.label': '{n} of {total}',
            's1.title': 'Train with intent.',
            's1.sub': 'A plan that adapts to how recovered you are.',
            's2.title': 'Every set, on your wrist.',
            's2.sub': 'Log sets from your iPhone, Apple Watch or Lock Screen, and never lose track of your rest.',
            's3.title': 'Progress, made visible.',
            's3.sub': 'Personal bests and training history, tracked automatically.',
            'welcome.start': 'Get started',
            'welcome.have': 'Already have an account?',
            'welcome.login': 'Log in',
            'legal.welcome': 'By continuing you agree to our <a data-legal="terms">Terms</a> and acknowledge our <a data-legal="privacy">Privacy Policy</a>.',

            'p1.eyebrow': 'Today · Recommended',
            'p1.title': 'Upper Body A',
            'p1.level': 'Good',
            'p1.chest': 'Chest',
            'p1.back': 'Back',
            'p1.arms': 'Arms',
            'p2.rest': 'Rest',
            'p2.skip': 'Skip',
            'p2.meta': 'Bench Press · Set 3 of 4',
            'p2.bpm': 'bpm',
            'p3.pill': 'New PR',
            'p3.title': 'Bench Press',
            'p3.meta': '100 kg × 5 · e1RM 117 kg',

            'sheet.close': 'Close',
            'seg.label': 'Account',
            'seg.signup': 'Sign up',
            'seg.login': 'Log in',
            'auth.signup.title': 'Create your account',
            'auth.signup.sub': 'Save your training and pick up on any device.',
            'auth.login.title': 'Welcome back',
            'auth.login.sub': 'Pick up right where you left off.',
            'auth.apple': 'Continue with Apple',
            'auth.or': 'or',
            'auth.email': 'Email',
            'auth.emailPh': 'name@example.com',
            'auth.password': 'Password',
            'auth.pwPh.signup': 'Choose a password',
            'auth.pwPh.login': 'Your password',
            'auth.hint': 'Use at least 8 characters.',
            'auth.err.email': 'Enter a valid email address.',
            'auth.err.pw': 'Use at least 8 characters.',
            'auth.err.pwLogin': 'Enter your password.',
            'auth.showPw': 'Show password',
            'auth.hidePw': 'Hide password',
            'auth.forgot': 'Forgot password?',
            'auth.submit.signup': 'Create account',
            'auth.submit.login': 'Log in',
            'auth.busy.signup': 'Creating account…',
            'auth.busy.login': 'Logging in…',
            'legal.signup': 'By creating an account you agree to our <a data-legal="terms">Terms</a> and acknowledge our <a data-legal="privacy">Privacy Policy</a>.',

            'setup.back': 'Back',
            'setup.progress': 'Setup progress, step {n} of {total}',
            'profile.title': 'What are you training for?',
            'profile.sub': 'Pick your main goal and your experience. Rebase tunes your plan to it.',
            'profile.goal': 'Main goal',
            'profile.level': 'Experience',
            'profile.continue': 'Continue',
            'goal.strength': 'Build strength',
            'goal.strength.sub': 'Plan, log and progress your lifts',
            'goal.active': 'Stay active & healthy',
            'goal.active.sub': 'Keep heart rate and daily activity in view',
            'goal.recover': 'Recover smarter',
            'goal.recover.sub': 'Know what’s ready and what needs rest',
            'goal.performance': 'Perform better',
            'goal.performance.sub': 'Train for a sport or an event',
            'level.beginner': 'Beginner',
            'level.intermediate': 'Intermediate',
            'level.advanced': 'Advanced',

            'health.title': 'Connect Apple Health',
            'health.sub': 'Rebase saves your finished workouts to Health.',
            'health.workouts': 'Workouts',
            'health.workouts.sub': 'Finished sessions saved to Health',
            'health.write': 'Write',
            'health.hr': 'Heart rate',
            'health.hr.sub': 'Live from your Watch, not read from Health',
            'health.watch': 'Watch',
            'health.body': 'Body weight',
            'health.body.sub': 'Optional sync, turned on later in Settings',
            'health.optional': 'Optional',
            'health.note': 'Your Apple Health data stays on your iPhone, and Rebase only uses what you allow. Change this anytime in Settings › Health. <a data-legal="privacy">Privacy details</a>',
            'health.connect': 'Connect Apple Health',
            'health.later': 'Not now',

            'coach.title': 'Add AI Coaching?',
            'coach.sub': 'An optional coach for chat and training plans. It stays off unless you turn it on.',
            'coach.shared': 'What the coach receives',
            'coach.r1': 'About you',
            'coach.r1.sub': 'Age range, sex, height, weight, goal and experience',
            'coach.r2': 'Health summaries',
            'coach.r2.sub': 'Scores and trends from your device, never raw readings',
            'coach.r3': 'Your questions',
            'coach.r3.sub': 'What you type to the coach',
            'coach.never': 'Your email, password and raw Apple Health readings are never sent. Your name is replaced by a placeholder. Everything is processed in the EU.',
            'coach.consent': 'By turning on AI Coaching you explicitly consent to your health data being processed for it. You can withdraw this anytime in Settings. <a data-legal="privacy">Details</a>',
            'coach.on': 'Turn on AI Coaching',
            'coach.off': 'No thanks',

            'notify.title': 'Never miss your next set',
            'notify.sub': 'Get a time-sensitive alert the moment your rest is over, even with your phone locked.',
            'notify.app': 'Rebase',
            'notify.time': 'now',
            'notify.body': '<b>Rest over.</b> Bench Press, set 3 of 4. Go!',
            'notify.p1': 'Rest-over alerts, even when your phone is locked',
            'notify.p2': 'A haptic tap on your Apple Watch',
            'notify.on': 'Turn on notifications',
            'notify.later': 'Not now',

            'done.title': 'You’re all set.',
            'done.sub': 'Your first workout is a tap away.',
            'done.health.on': 'Apple Health connected',
            'done.health.off': 'Apple Health: later',
            'done.coach.on': 'AI Coaching on',
            'done.coach.off': 'AI Coaching off',
            'done.notify.on': 'Notifications on',
            'done.notify.off': 'Notifications: later',
            'done.start': 'Start training',

            'toast.end': 'End of the prototype. Restarting the flow…',
            'toast.login': 'Logged in. The app would open your Strength hub now.',
            'toast.forgot': 'Prototype: the password reset would start here.',

            'panel.lead': 'Dark and video-led. Tap through the phone, or jump straight to a screen:',
            'panel.welcome': 'Welcome',
            'panel.signup': 'Sign up',
            'panel.login': 'Log in',
            'panel.profile': 'Profile',
            'panel.coach': 'AI Coaching',
            'panel.health': 'Apple Health',
            'panel.notify': 'Notifications',
            'panel.done': 'Done',
            'panel.language': 'Language',
            'panel.reduce': 'Preview reduced motion',
            'panel.fine': 'Nothing is sent or stored; the forms are not connected to anything. The design tokens mirror PulseTheme.swift, see the README.'
        },

        de: {
            'doc.title': 'Rebase – Onboarding & Anmeldung (Design-Prototyp)',
            'video.pause': 'Hintergrundvideo anhalten',
            'video.play': 'Hintergrundvideo abspielen',

            'welcome.h1': 'Willkommen bei Rebase',
            'pager.label': 'Highlights von Rebase',
            'pager.go': 'Highlight {n} von {total} anzeigen',
            'slide.label': '{n} von {total}',
            's1.title': 'Trainiere mit Ziel.',
            's1.sub': 'Ein Plan, der sich daran orientiert, wie erholt du bist.',
            's2.title': 'Jeder Satz am Handgelenk.',
            's2.sub': 'Logge Sätze am iPhone, an der Apple Watch oder auf dem Sperrbildschirm und behalte deine Pause im Blick.',
            's3.title': 'Fortschritt, sichtbar gemacht.',
            's3.sub': 'Bestleistungen und Trainingsverlauf, automatisch erfasst.',
            'welcome.start': 'Los geht’s',
            'welcome.have': 'Schon ein Konto?',
            'welcome.login': 'Anmelden',
            'legal.welcome': 'Wenn du fortfährst, akzeptierst du unsere <a data-legal="terms">AGB</a> und nimmst die <a data-legal="privacy">Datenschutzerklärung</a> zur Kenntnis.',

            'p1.eyebrow': 'Heute · Empfohlen',
            'p1.title': 'Oberkörper A',
            'p1.level': 'Gut',
            'p1.chest': 'Brust',
            'p1.back': 'Rücken',
            'p1.arms': 'Arme',
            'p2.rest': 'Pause',
            'p2.skip': 'Weiter',
            'p2.meta': 'Bankdrücken · Satz 3 von 4',
            'p2.bpm': 'bpm',
            'p3.pill': 'Neuer PR',
            'p3.title': 'Bankdrücken',
            'p3.meta': '100 kg × 5 · e1RM 117 kg',

            'sheet.close': 'Schließen',
            'seg.label': 'Konto',
            'seg.signup': 'Registrieren',
            'seg.login': 'Anmelden',
            'auth.signup.title': 'Konto erstellen',
            'auth.signup.sub': 'Sichere dein Training und mach auf jedem Gerät weiter.',
            'auth.login.title': 'Willkommen zurück',
            'auth.login.sub': 'Mach genau da weiter, wo du aufgehört hast.',
            'auth.apple': 'Weiter mit Apple',
            'auth.or': 'oder',
            'auth.email': 'E-Mail',
            'auth.emailPh': 'name@beispiel.de',
            'auth.password': 'Passwort',
            'auth.pwPh.signup': 'Wähle ein Passwort',
            'auth.pwPh.login': 'Dein Passwort',
            'auth.hint': 'Verwende mindestens 8 Zeichen.',
            'auth.err.email': 'Gib eine gültige E-Mail-Adresse ein.',
            'auth.err.pw': 'Verwende mindestens 8 Zeichen.',
            'auth.err.pwLogin': 'Gib dein Passwort ein.',
            'auth.showPw': 'Passwort anzeigen',
            'auth.hidePw': 'Passwort verbergen',
            'auth.forgot': 'Passwort vergessen?',
            'auth.submit.signup': 'Konto erstellen',
            'auth.submit.login': 'Anmelden',
            'auth.busy.signup': 'Konto wird erstellt …',
            'auth.busy.login': 'Anmeldung läuft …',
            'legal.signup': 'Mit der Kontoerstellung akzeptierst du unsere <a data-legal="terms">AGB</a> und nimmst die <a data-legal="privacy">Datenschutzerklärung</a> zur Kenntnis.',

            'setup.back': 'Zurück',
            'setup.progress': 'Einrichtung, Schritt {n} von {total}',
            'profile.title': 'Wofür trainierst du?',
            'profile.sub': 'Wähle dein Hauptziel und deine Erfahrung. Rebase stimmt deinen Plan darauf ab.',
            'profile.goal': 'Hauptziel',
            'profile.level': 'Erfahrung',
            'profile.continue': 'Weiter',
            'goal.strength': 'Kraft aufbauen',
            'goal.strength.sub': 'Training planen, loggen und steigern',
            'goal.active': 'Aktiv & gesund bleiben',
            'goal.active.sub': 'Herzfrequenz und Aktivität im Blick',
            'goal.recover': 'Besser erholen',
            'goal.recover.sub': 'Wissen, was bereit ist und was Pause braucht',
            'goal.performance': 'Leistung steigern',
            'goal.performance.sub': 'Für Sport oder ein Event trainieren',
            'level.beginner': 'Einsteiger',
            'level.intermediate': 'Fortgeschritten',
            'level.advanced': 'Erfahren',

            'health.title': 'Apple Health verbinden',
            'health.sub': 'Rebase speichert deine abgeschlossenen Workouts in Health.',
            'health.workouts': 'Workouts',
            'health.workouts.sub': 'Abgeschlossene Einheiten in Health sichern',
            'health.write': 'Schreiben',
            'health.hr': 'Herzfrequenz',
            'health.hr.sub': 'Live von der Watch, nicht aus Health gelesen',
            'health.watch': 'Watch',
            'health.body': 'Körpergewicht',
            'health.body.sub': 'Optionaler Abgleich, später in den Einstellungen',
            'health.optional': 'Optional',
            'health.note': 'Deine Apple-Health-Daten bleiben auf deinem iPhone, und Rebase nutzt nur, was du erlaubst. Das kannst du jederzeit unter Einstellungen › Health ändern. <a data-legal="privacy">Datenschutz-Details</a>',
            'health.connect': 'Apple Health verbinden',
            'health.later': 'Später',

            'coach.title': 'KI-Coaching hinzufügen?',
            'coach.sub': 'Ein optionaler Coach für Chat und Trainingspläne. Er bleibt aus, bis du ihn einschaltest.',
            'coach.shared': 'Das erhält der Coach',
            'coach.r1': 'Über dich',
            'coach.r1.sub': 'Altersgruppe, Geschlecht, Größe, Gewicht, Ziel und Erfahrung',
            'coach.r2': 'Gesundheits-Zusammenfassungen',
            'coach.r2.sub': 'Werte und Trends von deinem Gerät, nie Rohdaten',
            'coach.r3': 'Deine Fragen',
            'coach.r3.sub': 'Was du dem Coach schreibst',
            'coach.never': 'Deine E-Mail, dein Passwort und Rohdaten aus Apple Health werden nie gesendet. Dein Name wird durch einen Platzhalter ersetzt. Alles wird in der EU verarbeitet.',
            'coach.consent': 'Mit dem Einschalten willigst du ausdrücklich ein, dass deine Gesundheitsdaten für das KI-Coaching verarbeitet werden. Du kannst das jederzeit in den Einstellungen widerrufen. <a data-legal="privacy">Details</a>',
            'coach.on': 'KI-Coaching einschalten',
            'coach.off': 'Nein, danke',

            'notify.title': 'Verpasse keinen Satz',
            'notify.sub': 'Erhalte einen zeitkritischen Hinweis, sobald deine Pause vorbei ist, auch bei gesperrtem iPhone.',
            'notify.app': 'Rebase',
            'notify.time': 'jetzt',
            'notify.body': '<b>Pause vorbei.</b> Bankdrücken, Satz 3 von 4. Los!',
            'notify.p1': 'Hinweis am Pausenende, auch bei gesperrtem iPhone',
            'notify.p2': 'Haptisches Signal an der Apple Watch',
            'notify.on': 'Mitteilungen aktivieren',
            'notify.later': 'Später',

            'done.title': 'Alles bereit.',
            'done.sub': 'Dein erstes Training ist nur einen Tipp entfernt.',
            'done.health.on': 'Apple Health verbunden',
            'done.health.off': 'Apple Health: später',
            'done.coach.on': 'KI-Coaching an',
            'done.coach.off': 'KI-Coaching aus',
            'done.notify.on': 'Mitteilungen an',
            'done.notify.off': 'Mitteilungen: später',
            'done.start': 'Training starten',

            'toast.end': 'Ende des Prototyps. Der Ablauf startet neu …',
            'toast.login': 'Angemeldet. Die App würde jetzt deinen Kraft-Hub öffnen.',
            'toast.forgot': 'Prototyp: Hier würde das Zurücksetzen des Passworts beginnen.',

            'panel.lead': 'Dunkel und videogeführt. Tippe dich durch das Telefon oder springe direkt zu einem Screen:',
            'panel.welcome': 'Willkommen',
            'panel.signup': 'Registrieren',
            'panel.login': 'Anmelden',
            'panel.profile': 'Profil',
            'panel.coach': 'KI-Coaching',
            'panel.health': 'Apple Health',
            'panel.notify': 'Mitteilungen',
            'panel.done': 'Fertig',
            'panel.language': 'Sprache',
            'panel.reduce': 'Reduzierte Bewegung simulieren',
            'panel.fine': 'Es wird nichts gesendet oder gespeichert; die Formulare sind mit nichts verbunden. Die Design-Tokens entsprechen PulseTheme.swift, siehe README.'
        }
    };

    /* Legal pages that already exist next to this folder (the app links the same documents). */
    var LEGAL = {
        en: { terms: '../terms.html', privacy: '../privacy-policy.html' },
        de: { terms: '../agb.html', privacy: '../datenschutz.html' }
    };

    /* ----------------------------------------------------------------------
       Helpers and state
       ---------------------------------------------------------------------- */
    var SVG_NS = 'http://www.w3.org/2000/svg';
    var EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
    var SETUP = ['profile', 'health', 'coach', 'notify', 'done'];   // screens after sign-up, in order
    var STEPS = 4;                                                  // numbered steps (done is not one of them)
    var ROUTES = ['welcome', 'signup', 'login', 'profile', 'health', 'coach', 'notify', 'done'];

    var doc = document;
    var root = doc.documentElement;

    function $(selector, context) { return (context || doc).querySelector(selector); }
    function $$(selector, context) { return Array.prototype.slice.call((context || doc).querySelectorAll(selector)); }
    function byId(id) { return doc.getElementById(id); }
    function on(node, type, handler, options) { if (node) { node.addEventListener(type, handler, options); } }

    var device = byId('device');
    var slot = byId('device-slot');
    var welcome = byId('screen-welcome');
    var sheet = byId('sheet');
    var screens = SETUP.map(function (name) { return byId('screen-' + name); });

    var state = {
        lang: 'en',
        step: 'welcome',
        mode: 'signup',
        slide: 0,
        goal: null,
        level: null,
        health: null,   // null = not asked yet, true / false = answered
        coach: null,
        notify: null,
        userPaused: false,   // the pause button
        held: false,         // finger / pointer resting on the highlights
        busy: null,          // null | 'submit' | 'apple' while the fake request runs
        opener: null,        // the control that opened the sheet, so focus can return to it
        scale: 1
    };

    function t(key, params) {
        var table = STRINGS[state.lang] || STRINGS.en;
        var value = table[key];
        if (value == null) { value = STRINGS.en[key]; }
        if (value == null) { if (window.console) { console.warn('[rebase] missing string: ' + key); } return key; }
        if (params) {
            value = value.replace(/\{(\w+)\}/g, function (_, name) { return params[name] != null ? params[name] : ''; });
        }
        return value;
    }

    function reducedMotion() { return root.dataset.motion === 'reduced'; }
    function shouldAnimate() { return !state.userPaused && !reducedMotion() && !doc.hidden; }

    /* ----------------------------------------------------------------------
       Language
       ---------------------------------------------------------------------- */
    function applyLang(lang) {
        state.lang = STRINGS[lang] ? lang : 'en';
        root.lang = state.lang;
        doc.title = t('doc.title');

        $$('[data-i18n]').forEach(function (node) { node.textContent = t(node.getAttribute('data-i18n')); });
        $$('[data-i18n-html]').forEach(function (node) { node.innerHTML = t(node.getAttribute('data-i18n-html')); });
        $$('[data-i18n-attr]').forEach(function (node) {
            node.getAttribute('data-i18n-attr').split(';').forEach(function (pair) {
                var cut = pair.indexOf(':');
                node.setAttribute(pair.slice(0, cut), t(pair.slice(cut + 1)));
            });
        });

        renderDynamic();
    }

    /* Everything that depends on language AND state */
    function renderDynamic() {
        var total = 3;
        $$('#pager .bar').forEach(function (bar, i) {
            bar.setAttribute('aria-label', t('pager.go', { n: i + 1, total: total }));
        });
        $$('#slides .slide').forEach(function (slideEl, i) {
            slideEl.setAttribute('aria-label', t('slide.label', { n: i + 1, total: total }));
        });
        renderSheet();
        renderPasswordToggle();
        renderMotionButton();
        renderProgress();
        renderSummary();
        wireLegalLinks();
        updatePanel();
        requestAnimationFrame(updateScrollHints);
    }

    function wireLegalLinks() {
        $$('a[data-legal]').forEach(function (link) {
            link.href = LEGAL[state.lang][link.getAttribute('data-legal')];
            link.target = '_blank';
            link.rel = 'noopener';
        });
    }

    /* ----------------------------------------------------------------------
       Desktop frame: scale the phone to the window. On a phone it is full bleed.
       ---------------------------------------------------------------------- */
    var fullBleedQuery = window.matchMedia('(max-width: 520px)');

    function fit() {
        if (fullBleedQuery.matches) {
            slot.style.removeProperty('--s');
            state.scale = 1;
            return;
        }
        var panel = $('.panel');
        var panelWidth = panel && panel.offsetParent !== null ? panel.offsetWidth + 72 : 0;
        var scale = Math.min(1, (window.innerHeight - 56) / 852, (window.innerWidth - 48 - panelWidth) / 393);
        scale = Math.max(0.3, scale);
        state.scale = scale;
        slot.style.setProperty('--s', scale.toFixed(4));
    }

    /* ----------------------------------------------------------------------
       Background video
       ---------------------------------------------------------------------- */
    var video = byId('hero-video');
    var motionButton = byId('btn-motion');

    function dataSaver() {
        var connection = navigator.connection;
        return !!(connection && connection.saveData);
    }

    var videoTimer = 0;

    /* The clip only matters where it is visible: behind the welcome copy and above the sheet.
       Behind the setup veil its motion is barely visible, so it rests there to save battery. */
    function videoWanted() {
        return (state.step === 'welcome' || state.step === 'auth') && shouldAnimate() && !dataSaver();
    }

    function syncVideo() {
        if (!video) { return; }
        if (videoWanted()) {
            var attempt = video.play();
            if (attempt && attempt.catch) { attempt.catch(function () { /* autoplay blocked: the poster stays, the next tap retries */ }); }
        } else {
            video.pause();
        }
    }

    function renderMotionButton() {
        motionButton.setAttribute('aria-pressed', String(state.userPaused));
        motionButton.setAttribute('aria-label', t(state.userPaused ? 'video.play' : 'video.pause'));
        device.classList.toggle('is-paused', state.userPaused);
    }

    if (video) {
        video.muted = true;   // iOS only autoplays muted, inline video
        on(video, 'playing', function () { video.classList.add('is-playing'); });
    }
    on(motionButton, 'click', function () {
        state.userPaused = !state.userPaused;
        renderMotionButton();
        syncAll();
    });
    // Low Power Mode and some browsers block autoplay until the first touch
    on(doc, 'pointerdown', function () { if (video && video.paused && videoWanted()) { syncVideo(); } }, { passive: true });

    /* ----------------------------------------------------------------------
       Welcome: story-style highlights
       ---------------------------------------------------------------------- */
    var pagerEl = byId('pager');
    var bars = $$('#pager .bar');
    var slideEls = $$('#slides .slide');
    var proofEls = $$('#proofs .proof');
    var restTime = byId('rest-time');
    var restRing = byId('rest-ring');
    var rest = { total: 90, left: 84, timer: 0 };

    function pagerShouldRun() { return state.step === 'welcome' && !state.held && shouldAnimate(); }

    function setSlide(index) {
        var count = slideEls.length;
        state.slide = ((index % count) + count) % count;
        device.dataset.slide = String(state.slide);

        slideEls.forEach(function (node, i) {
            node.classList.toggle('is-active', i === state.slide);
            node.classList.toggle('is-before', i < state.slide);
            node.setAttribute('aria-hidden', String(i !== state.slide));
            node.inert = i !== state.slide;
        });
        proofEls.forEach(function (node, i) {
            node.classList.toggle('is-active', i === state.slide);
            node.classList.toggle('is-before', i < state.slide);
        });
        bars.forEach(function (bar, i) {
            bar.classList.remove('is-active');
            bar.classList.toggle('is-done', i < state.slide);
            bar.setAttribute('aria-current', String(i === state.slide));
        });
        void pagerEl.offsetWidth;   // restart the fill animation of the new segment
        bars[state.slide].classList.add('is-active');

        rest.left = 84;
        renderRest();
        syncRest();
    }

    function syncPager() { pagerEl.classList.toggle('is-paused', !pagerShouldRun()); }

    on(pagerEl, 'animationend', function (event) {
        if (event.animationName === 'bar-fill' && pagerShouldRun()) { setSlide(state.slide + 1); }
    });
    bars.forEach(function (bar, i) {
        on(bar, 'click', function () { setSlide(i); });
        on(bar, 'keydown', function (event) {
            if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
                event.preventDefault();
                var target = (state.slide + (event.key === 'ArrowRight' ? 1 : -1) + bars.length) % bars.length;
                setSlide(target);
                bars[target].focus();
            }
        });
    });

    // Hold to pause, swipe to move (like stories)
    (function swipe() {
        var zone = $('.welcome__block');
        var start = null;
        function isControl(target) { return target.closest && target.closest('button, a, input'); }
        on(zone, 'pointerdown', function (event) {
            if (isControl(event.target)) { return; }
            start = { x: event.clientX, y: event.clientY };
            state.held = true;
            syncPager();
        });
        function release(event, cancelled) {
            if (!start) { return; }
            var dx = (event.clientX - start.x) / state.scale;
            var dy = (event.clientY - start.y) / state.scale;
            start = null;
            state.held = false;
            syncPager();
            if (!cancelled && Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) { setSlide(state.slide + (dx < 0 ? 1 : -1)); }
        }
        on(doc, 'pointerup', function (event) { release(event, false); });
        on(doc, 'pointercancel', function (event) { release(event, true); });
    })();

    /* The rest-timer preview counts down while its highlight is on screen */
    function renderRest() {
        var minutes = Math.floor(rest.left / 60);
        var seconds = rest.left % 60;
        restTime.textContent = minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
        restRing.style.setProperty('--p', String(Math.round(rest.left / rest.total * 100)));
    }
    function syncRest() {
        clearInterval(rest.timer);
        rest.timer = 0;
        if (state.step === 'welcome' && state.slide === 1 && shouldAnimate()) {
            rest.timer = setInterval(function () {
                rest.left = Math.max(0, rest.left - 1);
                renderRest();
            }, 1000);
        }
    }

    /* ----------------------------------------------------------------------
       Sign up / log in sheet
       ---------------------------------------------------------------------- */
    var seg = byId('seg');
    var tabs = $$('#seg [role="tab"]');
    var form = byId('auth-form');
    var emailInput = byId('in-email');
    var passwordInput = byId('in-pw');
    var emailField = byId('field-email');
    var passwordField = byId('field-pw');
    var emailMessage = byId('msg-email');
    var passwordMessage = byId('msg-pw');
    var submitButton = byId('btn-submit');
    var forgotButton = byId('btn-forgot');
    var eyeButton = byId('btn-eye');

    function renderSheet() {
        var mode = state.mode;
        byId('sheet-title').textContent = t('auth.' + mode + '.title');
        byId('sheet-sub').textContent = t('auth.' + mode + '.sub');
        $('.btn__label', submitButton).textContent = t(state.busy === 'submit' ? 'auth.busy.' + mode : 'auth.submit.' + mode);
        passwordInput.placeholder = t('auth.pwPh.' + mode);
        passwordInput.setAttribute('enterkeyhint', 'go');
        forgotButton.parentNode.hidden = mode !== 'login';

        var legal = byId('sheet-legal');
        legal.hidden = mode !== 'signup';
        legal.innerHTML = mode === 'signup' ? t('legal.signup') : '';

        seg.dataset.mode = mode;
        tabs.forEach(function (tab) {
            var selected = tab.dataset.mode === mode;
            tab.setAttribute('aria-selected', String(selected));
            tab.tabIndex = selected ? 0 : -1;
        });
        byId('auth-panel').setAttribute('aria-labelledby', 'tab-' + mode);

        // Messages are re-rendered from the current error flags so a language switch keeps them
        renderMessages();
        wireLegalLinks();
    }

    var errors = { email: false, pw: false };

    function renderMessages() {
        emailMessage.textContent = errors.email ? t('auth.err.email') : '';
        emailField.classList.toggle('is-invalid', errors.email);
        emailInput.setAttribute('aria-invalid', String(errors.email));

        var signup = state.mode === 'signup';
        if (errors.pw) {
            passwordMessage.textContent = t(signup ? 'auth.err.pw' : 'auth.err.pwLogin');
        } else {
            passwordMessage.textContent = signup ? t('auth.hint') : '';
        }
        passwordMessage.classList.toggle('is-error', errors.pw);
        passwordMessage.classList.toggle('msg--hint', !errors.pw);
        passwordField.classList.toggle('is-invalid', errors.pw);
        passwordInput.setAttribute('aria-invalid', String(errors.pw));
    }

    function renderPasswordToggle() {
        var shown = passwordInput.type === 'text';
        eyeButton.setAttribute('aria-pressed', String(shown));
        eyeButton.setAttribute('aria-label', t(shown ? 'auth.hidePw' : 'auth.showPw'));
    }

    function setMode(mode, options) {
        if (mode === state.mode && !(options && options.force)) { return; }
        var animate = state.step === 'auth' && !reducedMotion() && sheet.animate;
        var before = animate ? sheet.offsetHeight : 0;

        state.mode = mode;
        errors.email = errors.pw = false;
        renderSheet();

        if (animate) {
            var after = sheet.offsetHeight;
            if (before && after && before !== after) {
                sheet.animate([{ height: before + 'px' }, { height: after + 'px' }], { duration: 320, easing: 'cubic-bezier(.2,.8,.2,1)' });
            }
        }
        updatePanel();
    }

    tabs.forEach(function (tab, i) {
        on(tab, 'click', function () { setMode(tab.dataset.mode); });
        on(tab, 'keydown', function (event) {
            if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') { return; }
            event.preventDefault();
            var next = tabs[(i + 1) % tabs.length];
            setMode(next.dataset.mode);
            next.focus();
        });
    });

    on(eyeButton, 'click', function () {
        passwordInput.type = passwordInput.type === 'password' ? 'text' : 'password';
        renderPasswordToggle();
        passwordInput.focus();
    });

    on(emailInput, 'input', function () { if (errors.email) { errors.email = false; renderMessages(); } });
    on(passwordInput, 'input', function () { if (errors.pw) { errors.pw = false; renderMessages(); } });

    on(form, 'submit', function (event) {
        event.preventDefault();
        if (state.busy) { return; }
        var emailOk = EMAIL_RE.test(emailInput.value.trim());
        var passwordOk = state.mode === 'signup' ? passwordInput.value.length >= 8 : passwordInput.value.length > 0;
        errors.email = !emailOk;
        errors.pw = !passwordOk;
        renderMessages();
        if (!emailOk) { emailInput.focus(); return; }
        if (!passwordOk) { passwordInput.focus(); return; }
        authenticate(submitButton);
    });

    on(byId('btn-apple'), 'click', function () { authenticate(byId('btn-apple')); });

    on(forgotButton, 'click', function () { toast(t('toast.forgot')); });

    /* Pretend to talk to the identity provider, then continue */
    function authenticate(button) {
        state.busy = button === submitButton ? 'submit' : 'apple';
        button.classList.add('is-busy');
        renderSheet();
        setTimeout(function () {
            state.busy = null;
            button.classList.remove('is-busy');
            renderSheet();
            if (state.step !== 'auth') { return; }   // closed in the meantime
            if (state.mode === 'signup') {
                go('profile');
            } else {
                toast(t('toast.login'));
                setTimeout(restart, 2200);
            }
        }, button === submitButton ? 950 : 650);
    }

    /* Drag the grabber down to dismiss, like a native sheet */
    (function dragToDismiss() {
        var grab = byId('sheet-grab');
        var drag = null;
        on(grab, 'pointerdown', function (event) {
            drag = { y: event.clientY, t: event.timeStamp, dy: 0 };
            sheet.classList.add('is-dragging');
            grab.setPointerCapture(event.pointerId);
        });
        on(grab, 'pointermove', function (event) {
            if (!drag) { return; }
            drag.dy = Math.max(0, (event.clientY - drag.y) / state.scale);
            sheet.style.transform = 'translateY(' + drag.dy + 'px)';
        });
        function end(event) {
            if (!drag) { return; }
            var distance = drag.dy;
            var speed = distance / Math.max(1, event.timeStamp - drag.t);
            drag = null;
            sheet.classList.remove('is-dragging');
            sheet.style.transform = '';
            if (distance > 110 || (distance > 36 && speed > 0.6)) { go('welcome'); }
        }
        on(grab, 'pointerup', end);
        on(grab, 'pointercancel', end);
    })();

    on(byId('sheet-close'), 'click', function () { go('welcome'); });
    on(byId('scrim'), 'click', function () { if (state.step === 'auth') { go('welcome'); } });
    on(doc, 'keydown', function (event) {
        if (event.key === 'Escape' && state.step === 'auth') { go('welcome'); }
    });

    // Keep the sheet above the on-screen keyboard (iOS Safari does not resize the layout viewport)
    if (window.visualViewport) {
        var viewport = window.visualViewport;
        var lift = function () {
            var keyboard = fullBleedQuery.matches ? Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop) : 0;
            device.style.setProperty('--kb', keyboard + 'px');
        };
        on(viewport, 'resize', lift);
        on(viewport, 'scroll', lift);
    }

    /* ----------------------------------------------------------------------
       Setup steps
       ---------------------------------------------------------------------- */
    var goalInputs = $$('input[name="goal"]');
    var levelInputs = $$('input[name="level"]');
    var profileNext = byId('btn-profile-next');

    function checkedValue(inputs) {
        var hit = inputs.filter(function (input) { return input.checked; })[0];
        return hit ? hit.value : null;
    }
    function syncProfile() {
        state.goal = checkedValue(goalInputs);
        state.level = checkedValue(levelInputs);
        profileNext.disabled = !(state.goal && state.level);
    }
    goalInputs.concat(levelInputs).forEach(function (input) { on(input, 'change', syncProfile); });

    on(profileNext, 'click', function () { go('health'); });
    on(byId('btn-health-yes'), 'click', function () { state.health = true; go('coach'); });
    on(byId('btn-coach-yes'), 'click', function () { state.coach = true; go('notify'); });
    on(byId('btn-coach-no'), 'click', function () { state.coach = false; go('notify'); });
    on(byId('btn-health-no'), 'click', function () { state.health = false; go('coach'); });
    on(byId('btn-notify-yes'), 'click', function () { state.notify = true; go('done'); });
    on(byId('btn-notify-no'), 'click', function () { state.notify = false; go('done'); });
    on(byId('btn-back'), 'click', function () {
        var index = SETUP.indexOf(state.step);
        if (index > 0) { go(SETUP[index - 1]); }
    });
    on(byId('btn-finish'), 'click', function () {
        toast(t('toast.end'));
        setTimeout(restart, 1900);
    });

    /* Fade the bottom edge of a setup screen's content while it can still scroll */
    function updateScrollHints() {
        $$('.setup__body').forEach(function (body) {
            var more = body.scrollHeight - body.clientHeight > 2 && body.scrollTop + body.clientHeight < body.scrollHeight - 2;
            body.dataset.more = String(more);
        });
    }
    $$('.setup__body').forEach(function (body) { on(body, 'scroll', updateScrollHints, { passive: true }); });
    on(window, 'resize', updateScrollHints);

    function renderProgress() {
        var progress = byId('progress');
        var index = SETUP.indexOf(state.step);
        var current = Math.min(Math.max(index, 0) + 1, STEPS);
        $$('i', progress).forEach(function (segment, i) { segment.classList.toggle('is-on', index >= 0 && i < current); });
        progress.setAttribute('aria-valuenow', String(current));
        progress.setAttribute('aria-valuemax', String(STEPS));
        progress.setAttribute('aria-label', t('setup.progress', { n: current, total: STEPS }));
    }

    function icon(id, size) {
        var svg = doc.createElementNS(SVG_NS, 'svg');
        svg.setAttribute('class', 'ico');
        svg.setAttribute('width', size);
        svg.setAttribute('height', size);
        svg.setAttribute('aria-hidden', 'true');
        var use = doc.createElementNS(SVG_NS, 'use');
        use.setAttribute('href', '#' + id);
        svg.appendChild(use);
        return svg;
    }

    function renderSummary() {
        var list = byId('summary');
        list.textContent = '';
        function add(label, ok) {
            var item = doc.createElement('li');
            if (ok) { item.appendChild(icon('i-check', 12)); } else { item.className = 'is-muted'; }
            item.appendChild(doc.createTextNode(label));
            list.appendChild(item);
        }
        if (state.goal) { add(t('goal.' + state.goal), true); }
        if (state.level) { add(t('level.' + state.level), true); }
        add(t(state.health ? 'done.health.on' : 'done.health.off'), !!state.health);
        add(t(state.coach ? 'done.coach.on' : 'done.coach.off'), !!state.coach);
        add(t(state.notify ? 'done.notify.on' : 'done.notify.off'), !!state.notify);
    }

    /* ----------------------------------------------------------------------
       Toast
       ---------------------------------------------------------------------- */
    var toastEl = byId('toast');
    var toastTimer = 0;
    function toast(message) {
        toastEl.textContent = message;
        toastEl.classList.add('is-visible');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { toastEl.classList.remove('is-visible'); }, 2400);
    }

    /* ----------------------------------------------------------------------
       Navigation
       ---------------------------------------------------------------------- */
    function routeName() { return state.step === 'auth' ? state.mode : state.step; }

    function focusTarget(step) {
        if (step === 'auth') { return byId('sheet-title'); }
        if (step === 'welcome') { return state.opener; }
        return $('h1', byId('screen-' + step));
    }

    function go(step, options) {
        options = options || {};
        var previous = state.step;
        if (step === 'auth' && options.mode) { setMode(options.mode); }

        state.step = step;
        device.dataset.step = step;
        device.dataset.phase = step === 'welcome' || step === 'auth' ? step : 'setup';

        welcome.inert = step !== 'welcome';
        sheet.inert = step !== 'auth';

        var active = SETUP.indexOf(step);
        screens.forEach(function (screen, i) {
            screen.classList.toggle('is-active', i === active);
            screen.classList.toggle('is-before', i < active);
            screen.inert = i !== active;
        });

        if (step === 'done') { renderSummary(); }
        renderProgress();
        syncPager();
        syncRest();
        requestAnimationFrame(updateScrollHints);
        clearTimeout(videoTimer);
        videoTimer = setTimeout(syncVideo, state.step === 'welcome' || state.step === 'auth' ? 0 : 900);   // let the veil fade in first
        updatePanel();
        if (history.replaceState) { history.replaceState(null, '', '#' + routeName()); }

        if (!options.silent && previous !== step) {
            var target = focusTarget(step);
            if (target && target.focus) { requestAnimationFrame(function () { target.focus({ preventScroll: true }); }); }
        }
    }

    function openAuth(mode, opener) {
        state.opener = opener || null;
        go('auth', { mode: mode });
    }
    on(byId('btn-start'), 'click', function (event) { openAuth('signup', event.currentTarget); });
    on(byId('btn-login'), 'click', function (event) { openAuth('login', event.currentTarget); });

    /* A direct jump (panel or deep link) should still look lived-in */
    function seedDemoChoices() {
        if (!state.goal || !state.level) {
            goalInputs.forEach(function (input) { input.checked = input.value === 'strength'; });
            levelInputs.forEach(function (input) { input.checked = input.value === 'intermediate'; });
            syncProfile();
        }
        if (state.health == null) { state.health = true; }
        if (state.coach == null) { state.coach = false; }   // off by default, like the app
        if (state.notify == null) { state.notify = true; }
    }

    function route(name, options) {
        if (ROUTES.indexOf(name) < 0) { name = 'welcome'; }
        if (name === 'signup' || name === 'login') {
            state.opener = null;
            go('auth', { mode: name, silent: options && options.silent });
            return;
        }
        if (name === 'health' || name === 'coach' || name === 'notify' || name === 'done') { seedDemoChoices(); }
        if (name === 'welcome') { setSlide(0); }
        go(name, options);
    }

    function restart() {
        goalInputs.concat(levelInputs).forEach(function (input) { input.checked = false; });
        syncProfile();
        state.health = state.coach = state.notify = null;
        emailInput.value = passwordInput.value = '';
        passwordInput.type = 'password';
        errors.email = errors.pw = false;
        state.mode = 'signup';
        renderSheet();
        renderPasswordToggle();
        setSlide(0);
        go('welcome', { silent: true });
        renderSummary();
    }

    /* ----------------------------------------------------------------------
       Desktop panel
       ---------------------------------------------------------------------- */
    function updatePanel() {
        var current = routeName();
        $$('#panel-steps button').forEach(function (button) {
            if (button.dataset.go === current) { button.setAttribute('aria-current', 'step'); } else { button.removeAttribute('aria-current'); }
        });
        $$('.panel__toggle button').forEach(function (button) {
            button.setAttribute('aria-pressed', String(button.dataset.lang === state.lang));
        });
    }

    $$('#panel-steps button').forEach(function (button) {
        on(button, 'click', function () { route(button.dataset.go); });
    });
    $$('.panel__toggle button').forEach(function (button) {
        on(button, 'click', function () { applyLang(button.dataset.lang); });
    });

    var systemReduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    var forcedReduced = false;
    function applyMotionPreference() {
        root.dataset.motion = forcedReduced || systemReduced.matches ? 'reduced' : 'full';
        syncAll();
    }
    on(byId('opt-reduce'), 'change', function (event) { forcedReduced = event.target.checked; applyMotionPreference(); });
    if (systemReduced.addEventListener) { systemReduced.addEventListener('change', applyMotionPreference); }

    function syncAll() {
        syncVideo();
        syncPager();
        syncRest();
    }
    on(doc, 'visibilitychange', syncAll);
    on(window, 'resize', fit);

    /* ----------------------------------------------------------------------
       Start
       ---------------------------------------------------------------------- */
    (function init() {
        var params = new URLSearchParams(window.location.search);
        var wanted = (params.get('lang') || navigator.language || 'en').slice(0, 2).toLowerCase();

        fit();
        applyLang(wanted === 'de' ? 'de' : 'en');
        syncProfile();
        setSlide(0);
        applyMotionPreference();
        route(window.location.hash.replace('#', '') || 'welcome', { silent: true });
        setTimeout(function () { device.classList.remove('is-intro'); }, 2200);
    })();
})();
