#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The account sheet over the hero clip: a Sign up / Log in switch, "Continue with Apple", and the email form. A system sheet, so
/// the keyboard, dragging down to close and VoiceOver's escape gesture work as everywhere else in iOS.
@MainActor
struct OnboardingAuthSheet: View {
    @ObservedObject var model: OnboardingModel
    /// The height of the content, for the sheet's first detent (the sheet is as tall as its form, and can be pulled up).
    @Binding var contentHeight: CGFloat

    @FocusState private var focus: AuthField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var copy: OnboardingCopy { model.copy }
    private var isSignUp: Bool { model.authMode == .signUp }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                modePicker
                header
                appleButton
                separator
                form
                legal
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 20)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: OnboardingSheetHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onPreferenceChange(OnboardingSheetHeightKey.self) { (height: CGFloat) in
            contentHeight = height
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(copy.keyboardDone) {
                    focus = nil
                }
                .accessibilityIdentifier("onboarding.keyboardDone")
            }
        }
        .onChange(of: model.focusRequest) { (_: AuthFocusRequest?, request: AuthFocusRequest?) in
            if let field = request?.field {
                focus = field
            }
        }
        .onChange(of: model.authMessage) { (_: String?, message: String?) in
            if let message = message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var closeButton: some View {
        Button {
            model.closeAuth()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
        }
        .buttonStyle(OnboardingRoundButtonStyle())
        .disabled(model.isBusy)
        .padding(.top, 10)
        .padding(.trailing, 12)
        .accessibilityLabel(copy.text(.sheetClose))
        .accessibilityIdentifier("onboarding.close")
    }

    private var modePicker: some View {
        OnboardingModePicker(
            selection: model.authMode,
            signUpTitle: copy.text(.segmentSignup),
            logInTitle: copy.text(.segmentLogin),
            isEnabled: !model.isBusy,
            onSelect: { (mode: AuthMode) in
                model.selectAuthMode(mode)
            }
        )
        .padding(.trailing, 46)
        .accessibilityLabel(copy.text(.segmentLabel))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(copy.text(isSignUp ? .authSignupTitle : .authLoginTitle))
                .pulseFont(22, .bold, relativeTo: .title2)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(copy.text(isSignUp ? .authSignupSub : .authLoginSub))
                .pulseFont(15, .regular, relativeTo: .subheadline)
                .foregroundStyle(OnboardingTheme.onMediaSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    // MARK: Apple and the separator

    private var appleButton: some View {
        Button {
            Task {
                await model.continueWithApple()
            }
        } label: {
            HStack(spacing: 8) {
                if model.busy == .apple {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.black)
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(copy.text(.authApple))
            }
        }
        .buttonStyle(OnboardingAppleButtonStyle())
        .disabled(model.isBusy)
        .opacity(model.busy == .apple ? 0.85 : 1)
        .accessibilityIdentifier("onboarding.apple")
    }

    private var separator: some View {
        HStack(spacing: 12) {
            Rectangle().fill(OnboardingTheme.separator).frame(height: 0.5)
            Text(copy.text(.authOr))
                .pulseFont(13, .regular, relativeTo: .footnote)
                .foregroundStyle(OnboardingTheme.onMediaTertiary)
            Rectangle().fill(OnboardingTheme.separator).frame(height: 0.5)
        }
        .padding(.vertical, 14)
        .accessibilityHidden(true)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            emailField
            message(for: model.emailIsInvalid ? copy.text(.authErrorEmail) : nil, isError: true)
            passwordField
                .padding(.top, 10)
            message(for: passwordMessage, isError: model.passwordIsInvalid)
            if !isSignUp {
                forgotRow
            }
            if let failure = model.authMessage {
                Text(failure)
                    .pulseFont(13, .regular, relativeTo: .footnote)
                    .foregroundStyle(OnboardingTheme.destructiveText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                    .accessibilityIdentifier("onboarding.authError")
            }
            submitButton
                .padding(.top, 14)
        }
    }

    /// Sign up shows the password rule as a hint; it turns into the error when the password is too short. Log in shows only errors.
    private var passwordMessage: String? {
        if model.passwordIsInvalid {
            return copy.text(isSignUp ? .authErrorPasswordShort : .authErrorPasswordLogin)
        }
        return isSignUp ? copy.text(.authPasswordHint) : nil
    }

    private func message(for text: String?, isError: Bool) -> some View {
        Group {
            if let text = text {
                Text(text)
                    .pulseFont(13, .regular, relativeTo: .footnote)
                    .foregroundStyle(isError ? OnboardingTheme.destructiveText : OnboardingTheme.onMediaTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
            }
        }
    }

    private var emailField: some View {
        OnboardingField(title: copy.text(.authEmail), isFocused: focus == .email, isInvalid: model.emailIsInvalid) {
            TextField(copy.text(.authEmail), text: $model.email, prompt: Text(copy.text(.authEmailPlaceholder)).foregroundColor(OnboardingTheme.placeholder))
                .focused($focus, equals: .email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.next)
                .onSubmit {
                    focus = .password
                }
                .onChange(of: model.email) { (_: String, _: String) in
                    model.fieldEdited(.email)
                }
                .accessibilityIdentifier("onboarding.email")
        }
        .disabled(model.isBusy)
    }

    private var passwordField: some View {
        OnboardingField(title: copy.text(.authPassword), isFocused: focus == .password, isInvalid: model.passwordIsInvalid, trailingInset: 44) {
            passwordInput
        }
        .overlay(alignment: .trailing) {
            Button {
                model.isPasswordVisible.toggle()
                focus = .password
            } label: {
                Image(systemName: model.isPasswordVisible ? "eye.slash" : "eye")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(OnboardingTheme.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PulsePlainButtonStyle())
            .padding(.trailing, 2)
            .accessibilityLabel(copy.text(model.isPasswordVisible ? .authHidePassword : .authShowPassword))
            .accessibilityIdentifier("onboarding.showPassword")
        }
        .disabled(model.isBusy)
    }

    /// A secure field, or a plain one while the password is shown. Both keep the focus on `.password`.
    @ViewBuilder
    private var passwordInput: some View {
        let placeholder = copy.text(isSignUp ? .authPasswordPlaceholderSignup : .authPasswordPlaceholderLogin)
        if model.isPasswordVisible {
            TextField(copy.text(.authPassword), text: $model.password, prompt: Text(placeholder).foregroundColor(OnboardingTheme.placeholder))
                .focused($focus, equals: .password)
                .textContentType(isSignUp ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.go)
                .onSubmit(submit)
                .onChange(of: model.password) { (_: String, _: String) in
                    model.fieldEdited(.password)
                }
                .accessibilityIdentifier("onboarding.password")
        } else {
            SecureField(copy.text(.authPassword), text: $model.password, prompt: Text(placeholder).foregroundColor(OnboardingTheme.placeholder))
                .focused($focus, equals: .password)
                .textContentType(isSignUp ? .newPassword : .password)
                .submitLabel(.go)
                .onSubmit(submit)
                .onChange(of: model.password) { (_: String, _: String) in
                    model.fieldEdited(.password)
                }
                .accessibilityIdentifier("onboarding.password")
        }
    }

    private var forgotRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                focus = nil
                Task {
                    await model.forgotPassword()
                }
            } label: {
                Text(copy.text(.authForgot))
            }
            .buttonStyle(OnboardingLinkButtonStyle())
            .disabled(model.isBusy)
            .accessibilityIdentifier("onboarding.forgot")
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if model.busy == .submit {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.black)
                }
                Text(submitTitle)
            }
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .disabled(model.isBusy)
        .accessibilityIdentifier("onboarding.submit")
    }

    private var submitTitle: String {
        if model.busy == .submit {
            return copy.text(isSignUp ? .authBusySignup : .authBusyLogin)
        }
        return copy.text(isSignUp ? .authSubmitSignup : .authSubmitLogin)
    }

    private func submit() {
        focus = nil
        Task {
            await model.submit()
        }
    }

    // MARK: Legal

    @ViewBuilder
    private var legal: some View {
        if isSignUp {
            Text(OnboardingRichText.attributed(copy.legalSignup, copy: copy))
                .pulseFont(12, .regular, relativeTo: .caption)
                .foregroundStyle(OnboardingTheme.onMediaTertiary)
                .tint(OnboardingTheme.onMediaSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }
}

// MARK: - Pieces

/// The height of the sheet's content, reported up to the screen that presents the sheet.
struct OnboardingSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A field with its label above the text, on a rounded fill that lights up while it has the focus.
private struct OnboardingField<Input: View>: View {
    let title: String
    let isFocused: Bool
    let isInvalid: Bool
    var trailingInset: CGFloat = 0
    private let input: Input

    init(title: String, isFocused: Bool, isInvalid: Bool, trailingInset: CGFloat = 0, @ViewBuilder input: () -> Input) {
        self.title = title
        self.isFocused = isFocused
        self.isInvalid = isInvalid
        self.trailingInset = trailingInset
        self.input = input()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .pulseFont(12, .medium, relativeTo: .caption)
                .foregroundStyle(OnboardingTheme.inkSecondary)
                .accessibilityHidden(true)
            input
                .pulseFont(17, .regular, relativeTo: .body)
                .foregroundStyle(Color.white)
                .tint(OnboardingTheme.green)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14 + trailingInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(isFocused ? Color(onboardingHex: 0x767680, opacity: 0.34) : OnboardingTheme.chipFill, in: shape)
        .overlay(
            shape.strokeBorder(
                isInvalid ? OnboardingTheme.destructive : (isFocused ? OnboardingTheme.nextRowRing : Color.clear),
                lineWidth: 2
            )
        )
        .animation(Animation.easeOut(duration: 0.2), value: isFocused)
        .accessibilityElement(children: .contain)
    }
}

/// The Sign up / Log in switch: a segmented control whose thumb slides.
private struct OnboardingModePicker: View {
    let selection: AuthMode
    let signUpTitle: String
    let logInTitle: String
    let isEnabled: Bool
    let onSelect: (AuthMode) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumbNamespace

    var body: some View {
        HStack(spacing: 0) {
            segment(signUpTitle, mode: .signUp, identifier: "onboarding.tab.signup")
            segment(logInTitle, mode: .logIn, identifier: "onboarding.tab.login")
        }
        .padding(2)
        .frame(height: 36)
        .background(OnboardingTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(reduceMotion ? nil : Animation.spring(response: 0.35, dampingFraction: 0.85), value: selection)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ title: String, mode: AuthMode, identifier: String) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Text(title)
                .pulseFont(14, .semibold, relativeTo: .subheadline)
                .foregroundStyle(selection == mode ? Color.white : OnboardingTheme.onMediaSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selection == mode {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(onboardingHex: 0x636366))
                            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 3)
                            .matchedGeometryEffect(id: "thumb", in: thumbNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .disabled(!isEnabled)
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
#endif
