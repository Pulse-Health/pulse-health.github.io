// OnboardingCopyTables.swift
//
// The words of the onboarding in English and German, ported from the reviewed design prototype (design/app.js).
// Every key is a case of `OnboardingText`; each language is an exhaustive `switch`, so a missing translation is a compile error.
// Text with links, bold parts or parameters lives in OnboardingCopy.swift.
//
// German uses the informal "du" like the plain-language privacy summary (datenschutz-einfach.html).

import Foundation

/// Every plain string of the onboarding.
public enum OnboardingText: CaseIterable, Hashable, Sendable {

    // video
    case videoPause
    case videoPlay

    // welcome
    case welcomeHeading

    // pager
    case pagerLabel

    // s1
    case highlight1Title
    case highlight1Sub

    // s2
    case highlight2Title
    case highlight2Sub

    // s3
    case highlight3Title
    case highlight3Sub

    // welcome
    case welcomeStart
    case welcomeHaveAccount
    case welcomeLogin

    // p1
    case previewPlanEyebrow
    case previewPlanTitle
    case previewPlanReadiness
    case previewPlanChest
    case previewPlanBack
    case previewPlanArms

    // p2
    case previewRestLabel
    case previewRestSkip
    case previewRestMeta
    case previewRestBpm

    // p3
    case previewRecordPill
    case previewRecordTitle
    case previewRecordMeta

    // sheet
    case sheetClose

    // seg
    case segmentLabel
    case segmentSignup
    case segmentLogin

    // auth
    case authSignupTitle
    case authSignupSub
    case authLoginTitle
    case authLoginSub
    case authApple
    case authOr
    case authEmail
    case authEmailPlaceholder
    case authPassword
    case authPasswordPlaceholderSignup
    case authPasswordPlaceholderLogin
    case authPasswordHint
    case authErrorEmail
    case authErrorPasswordShort
    case authErrorPasswordLogin
    case authShowPassword
    case authHidePassword
    case authForgot
    case authSubmitSignup
    case authSubmitLogin
    case authBusySignup
    case authBusyLogin

    // setup
    case setupBack

    // profile
    case profileTitle
    case profileSub
    case profileGoal
    case profileLevel
    case profileContinue

    // goal
    case goalStrength
    case goalStrengthSub
    case goalActive
    case goalActiveSub
    case goalRecover
    case goalRecoverSub
    case goalPerformance
    case goalPerformanceSub

    // level
    case levelBeginner
    case levelIntermediate
    case levelAdvanced

    // health
    case healthTitle
    case healthSub
    case healthHeartRate
    case healthHeartRateSub
    case healthWorkouts
    case healthWorkoutsSub
    case healthBody
    case healthBodySub
    case healthRead
    case healthWrite
    case healthConnect
    case healthLater

    // coach
    case coachTitle
    case coachSub
    case coachShared
    case coachRow1
    case coachRow1Sub
    case coachRow2
    case coachRow2Sub
    case coachRow3
    case coachRow3Sub
    case coachNever
    case coachOn
    case coachOff

    // notify
    case notifyTitle
    case notifySub
    case notifyApp
    case notifyTime
    case notifyPoint1
    case notifyPoint2
    case notifyOn
    case notifyLater

    // done
    case doneTitle
    case doneSub
    case doneHealthOn
    case doneHealthOff
    case doneCoachOn
    case doneCoachOff
    case doneNotifyOn
    case doneNotifyOff
    case doneStart
}

extension OnboardingCopy {
    var brand: String { OnboardingBrand.name }

    func english(_ key: OnboardingText) -> String {
        switch key {

        // video
        case .videoPause: return "Pause background video"
        case .videoPlay: return "Play background video"

        // welcome
        case .welcomeHeading: return "Welcome to \(brand)"

        // pager
        case .pagerLabel: return "\(brand) highlights"

        // s1
        case .highlight1Title: return "Train with intent."
        case .highlight1Sub: return "A plan that adapts to how recovered you are."

        // s2
        case .highlight2Title: return "Every set, on your wrist."
        case .highlight2Sub: return "Log sets from your iPhone, Apple Watch or Lock Screen, and never lose track of your rest."

        // s3
        case .highlight3Title: return "Progress, made visible."
        case .highlight3Sub: return "Personal bests and training history, tracked automatically."

        // welcome
        case .welcomeStart: return "Get started"
        case .welcomeHaveAccount: return "Already have an account?"
        case .welcomeLogin: return "Log in"

        // p1
        case .previewPlanEyebrow: return "Today · Recommended"
        case .previewPlanTitle: return "Upper Body A"
        case .previewPlanReadiness: return "Good"
        case .previewPlanChest: return "Chest"
        case .previewPlanBack: return "Back"
        case .previewPlanArms: return "Arms"

        // p2
        case .previewRestLabel: return "Rest"
        case .previewRestSkip: return "Skip"
        case .previewRestMeta: return "Bench Press · Set 3 of 4"
        case .previewRestBpm: return "bpm"

        // p3
        case .previewRecordPill: return "New PR"
        case .previewRecordTitle: return "Bench Press"
        case .previewRecordMeta: return "100 kg × 5 · e1RM 117 kg"

        // sheet
        case .sheetClose: return "Close"

        // seg
        case .segmentLabel: return "Account"
        case .segmentSignup: return "Sign up"
        case .segmentLogin: return "Log in"

        // auth
        case .authSignupTitle: return "Create your account"
        case .authSignupSub: return "Save your training and pick up on any device."
        case .authLoginTitle: return "Welcome back"
        case .authLoginSub: return "Pick up right where you left off."
        case .authApple: return "Continue with Apple"
        case .authOr: return "or"
        case .authEmail: return "Email"
        case .authEmailPlaceholder: return "name@example.com"
        case .authPassword: return "Password"
        case .authPasswordPlaceholderSignup: return "Choose a password"
        case .authPasswordPlaceholderLogin: return "Your password"
        case .authPasswordHint: return "Use at least 8 characters."
        case .authErrorEmail: return "Enter a valid email address."
        case .authErrorPasswordShort: return "Use at least 8 characters."
        case .authErrorPasswordLogin: return "Enter your password."
        case .authShowPassword: return "Show password"
        case .authHidePassword: return "Hide password"
        case .authForgot: return "Forgot password?"
        case .authSubmitSignup: return "Create account"
        case .authSubmitLogin: return "Log in"
        case .authBusySignup: return "Creating account…"
        case .authBusyLogin: return "Logging in…"

        // setup
        case .setupBack: return "Back"

        // profile
        case .profileTitle: return "What are you training for?"
        case .profileSub: return "Pick your main goal and your experience. \(brand) tunes your plan to it."
        case .profileGoal: return "Main goal"
        case .profileLevel: return "Experience"
        case .profileContinue: return "Continue"

        // goal
        case .goalStrength: return "Build strength"
        case .goalStrengthSub: return "Plan, log and progress your lifts"
        case .goalActive: return "Stay active & healthy"
        case .goalActiveSub: return "Keep heart rate and daily activity in view"
        case .goalRecover: return "Recover smarter"
        case .goalRecoverSub: return "Know what’s ready and what needs rest"
        case .goalPerformance: return "Perform better"
        case .goalPerformanceSub: return "Train for a sport or an event"

        // level
        case .levelBeginner: return "Beginner"
        case .levelIntermediate: return "Intermediate"
        case .levelAdvanced: return "Advanced"

        // health
        case .healthTitle: return "Connect Apple Health"
        case .healthSub: return "\(brand) reads your heart rate and active energy during a strength workout and saves finished workouts to Health."
        case .healthHeartRate: return "Heart rate & energy"
        case .healthHeartRateSub: return "Live on iPhone, Watch and Lock Screen"
        case .healthWorkouts: return "Workouts"
        case .healthWorkoutsSub: return "Finished sessions saved to Health"
        case .healthBody: return "Sleep & body profile"
        case .healthBodySub: return "For recovery, plus age range, sex, height and weight"
        case .healthRead: return "Read"
        case .healthWrite: return "Write"
        case .healthConnect: return "Connect Apple Health"
        case .healthLater: return "Not now"

        // coach
        case .coachTitle: return "Add AI Coaching?"
        case .coachSub: return "An optional coach for chat and training plans. It stays off unless you turn it on."
        case .coachShared: return "What the coach receives"
        case .coachRow1: return "About you"
        case .coachRow1Sub: return "Age range, sex, height, weight, goal and experience"
        case .coachRow2: return "Health summaries"
        case .coachRow2Sub: return "Scores and trends from your device, never raw readings"
        case .coachRow3: return "Your questions"
        case .coachRow3Sub: return "What you type to the coach"
        case .coachNever: return "Your email, password and raw Apple Health readings are never sent. Your name is replaced by a placeholder. Everything is processed in the EU."
        case .coachOn: return "Turn on AI Coaching"
        case .coachOff: return "No thanks"

        // notify
        case .notifyTitle: return "Never miss your next set"
        case .notifySub: return "Get a time-sensitive alert the moment your rest is over, even with your phone locked."
        case .notifyApp: return "\(brand)"
        case .notifyTime: return "now"
        case .notifyPoint1: return "Rest-over alerts, even when your phone is locked"
        case .notifyPoint2: return "A haptic tap on your Apple Watch"
        case .notifyOn: return "Turn on notifications"
        case .notifyLater: return "Not now"

        // done
        case .doneTitle: return "You’re all set."
        case .doneSub: return "Your first workout is a tap away."
        case .doneHealthOn: return "Apple Health connected"
        case .doneHealthOff: return "Apple Health: later"
        case .doneCoachOn: return "AI Coaching on"
        case .doneCoachOff: return "AI Coaching off"
        case .doneNotifyOn: return "Notifications on"
        case .doneNotifyOff: return "Notifications: later"
        case .doneStart: return "Start training"
        }
    }

    func german(_ key: OnboardingText) -> String {
        switch key {

        // video
        case .videoPause: return "Hintergrundvideo anhalten"
        case .videoPlay: return "Hintergrundvideo abspielen"

        // welcome
        case .welcomeHeading: return "Willkommen bei \(brand)"

        // pager
        case .pagerLabel: return "Highlights von \(brand)"

        // s1
        case .highlight1Title: return "Trainiere mit Ziel."
        case .highlight1Sub: return "Ein Plan, der sich daran orientiert, wie erholt du bist."

        // s2
        case .highlight2Title: return "Jeder Satz am Handgelenk."
        case .highlight2Sub: return "Logge Sätze am iPhone, an der Apple Watch oder auf dem Sperrbildschirm und behalte deine Pause im Blick."

        // s3
        case .highlight3Title: return "Fortschritt, sichtbar gemacht."
        case .highlight3Sub: return "Bestleistungen und Trainingsverlauf, automatisch erfasst."

        // welcome
        case .welcomeStart: return "Los geht’s"
        case .welcomeHaveAccount: return "Schon ein Konto?"
        case .welcomeLogin: return "Anmelden"

        // p1
        case .previewPlanEyebrow: return "Heute · Empfohlen"
        case .previewPlanTitle: return "Oberkörper A"
        case .previewPlanReadiness: return "Gut"
        case .previewPlanChest: return "Brust"
        case .previewPlanBack: return "Rücken"
        case .previewPlanArms: return "Arme"

        // p2
        case .previewRestLabel: return "Pause"
        case .previewRestSkip: return "Weiter"
        case .previewRestMeta: return "Bankdrücken · Satz 3 von 4"
        case .previewRestBpm: return "bpm"

        // p3
        case .previewRecordPill: return "Neuer PR"
        case .previewRecordTitle: return "Bankdrücken"
        case .previewRecordMeta: return "100 kg × 5 · e1RM 117 kg"

        // sheet
        case .sheetClose: return "Schließen"

        // seg
        case .segmentLabel: return "Konto"
        case .segmentSignup: return "Registrieren"
        case .segmentLogin: return "Anmelden"

        // auth
        case .authSignupTitle: return "Konto erstellen"
        case .authSignupSub: return "Sichere dein Training und mach auf jedem Gerät weiter."
        case .authLoginTitle: return "Willkommen zurück"
        case .authLoginSub: return "Mach genau da weiter, wo du aufgehört hast."
        case .authApple: return "Weiter mit Apple"
        case .authOr: return "oder"
        case .authEmail: return "E-Mail"
        case .authEmailPlaceholder: return "name@beispiel.de"
        case .authPassword: return "Passwort"
        case .authPasswordPlaceholderSignup: return "Wähle ein Passwort"
        case .authPasswordPlaceholderLogin: return "Dein Passwort"
        case .authPasswordHint: return "Verwende mindestens 8 Zeichen."
        case .authErrorEmail: return "Gib eine gültige E-Mail-Adresse ein."
        case .authErrorPasswordShort: return "Verwende mindestens 8 Zeichen."
        case .authErrorPasswordLogin: return "Gib dein Passwort ein."
        case .authShowPassword: return "Passwort anzeigen"
        case .authHidePassword: return "Passwort verbergen"
        case .authForgot: return "Passwort vergessen?"
        case .authSubmitSignup: return "Konto erstellen"
        case .authSubmitLogin: return "Anmelden"
        case .authBusySignup: return "Konto wird erstellt …"
        case .authBusyLogin: return "Anmeldung läuft …"

        // setup
        case .setupBack: return "Zurück"

        // profile
        case .profileTitle: return "Wofür trainierst du?"
        case .profileSub: return "Wähle dein Hauptziel und deine Erfahrung. \(brand) stimmt deinen Plan darauf ab."
        case .profileGoal: return "Hauptziel"
        case .profileLevel: return "Erfahrung"
        case .profileContinue: return "Weiter"

        // goal
        case .goalStrength: return "Kraft aufbauen"
        case .goalStrengthSub: return "Training planen, loggen und steigern"
        case .goalActive: return "Aktiv & gesund bleiben"
        case .goalActiveSub: return "Herzfrequenz und Aktivität im Blick"
        case .goalRecover: return "Besser erholen"
        case .goalRecoverSub: return "Wissen, was bereit ist und was Pause braucht"
        case .goalPerformance: return "Leistung steigern"
        case .goalPerformanceSub: return "Für Sport oder ein Event trainieren"

        // level
        case .levelBeginner: return "Einsteiger"
        case .levelIntermediate: return "Fortgeschritten"
        case .levelAdvanced: return "Erfahren"

        // health
        case .healthTitle: return "Apple Health verbinden"
        case .healthSub: return "\(brand) liest beim Krafttraining deine Herzfrequenz und aktive Energie und speichert abgeschlossene Workouts in Health."
        case .healthHeartRate: return "Herzfrequenz & Energie"
        case .healthHeartRateSub: return "Live auf iPhone, Watch und Sperrbildschirm"
        case .healthWorkouts: return "Workouts"
        case .healthWorkoutsSub: return "Abgeschlossene Einheiten in Health sichern"
        case .healthBody: return "Schlaf & Körperprofil"
        case .healthBodySub: return "Für die Erholung sowie Altersgruppe, Geschlecht, Größe und Gewicht"
        case .healthRead: return "Lesen"
        case .healthWrite: return "Schreiben"
        case .healthConnect: return "Apple Health verbinden"
        case .healthLater: return "Später"

        // coach
        case .coachTitle: return "KI-Coaching hinzufügen?"
        case .coachSub: return "Ein optionaler Coach für Chat und Trainingspläne. Er bleibt aus, bis du ihn einschaltest."
        case .coachShared: return "Das erhält der Coach"
        case .coachRow1: return "Über dich"
        case .coachRow1Sub: return "Altersgruppe, Geschlecht, Größe, Gewicht, Ziel und Erfahrung"
        case .coachRow2: return "Gesundheits-Zusammenfassungen"
        case .coachRow2Sub: return "Werte und Trends von deinem Gerät, nie Rohdaten"
        case .coachRow3: return "Deine Fragen"
        case .coachRow3Sub: return "Was du dem Coach schreibst"
        case .coachNever: return "Deine E-Mail, dein Passwort und Rohdaten aus Apple Health werden nie gesendet. Dein Name wird durch einen Platzhalter ersetzt. Alles wird in der EU verarbeitet."
        case .coachOn: return "KI-Coaching einschalten"
        case .coachOff: return "Nein, danke"

        // notify
        case .notifyTitle: return "Verpasse keinen Satz"
        case .notifySub: return "Erhalte einen zeitkritischen Hinweis, sobald deine Pause vorbei ist, auch bei gesperrtem iPhone."
        case .notifyApp: return "\(brand)"
        case .notifyTime: return "jetzt"
        case .notifyPoint1: return "Hinweis am Pausenende, auch bei gesperrtem iPhone"
        case .notifyPoint2: return "Haptisches Signal an der Apple Watch"
        case .notifyOn: return "Mitteilungen aktivieren"
        case .notifyLater: return "Später"

        // done
        case .doneTitle: return "Alles bereit."
        case .doneSub: return "Dein erstes Training ist nur einen Tipp entfernt."
        case .doneHealthOn: return "Apple Health verbunden"
        case .doneHealthOff: return "Apple Health: später"
        case .doneCoachOn: return "KI-Coaching an"
        case .doneCoachOff: return "KI-Coaching aus"
        case .doneNotifyOn: return "Mitteilungen an"
        case .doneNotifyOff: return "Mitteilungen: später"
        case .doneStart: return "Training starten"
        }
    }
}
