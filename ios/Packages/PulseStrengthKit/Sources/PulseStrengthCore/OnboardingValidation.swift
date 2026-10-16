import Foundation

/// What is wrong with the email and password a user typed.
public struct CredentialsCheck: Equatable, Hashable, Sendable {
    public var emailIsValid: Bool
    public var passwordIsValid: Bool

    public init(emailIsValid: Bool, passwordIsValid: Bool) {
        self.emailIsValid = emailIsValid
        self.passwordIsValid = passwordIsValid
    }

    public var isValid: Bool {
        emailIsValid && passwordIsValid
    }
}

/// Client-side checks of the account form. The identity provider has the last word; these only catch typos before a request is made.
public enum CredentialsValidator {
    /// A new password needs at least this many characters.
    public static let minimumPasswordLength = 8

    /// One "@" with something before it, and a domain that has a dot followed by at least two characters. No spaces.
    /// (The same rule as the prototype's `/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/`.) Leading and trailing spaces are ignored.
    public static func isValidEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(where: { $0.isWhitespace }) { return false }

        let parts = trimmed.split(separator: "@", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = Array(parts[1])
        if local.isEmpty { return false }

        // A dot that is not the first character and leaves at least two characters after it.
        guard domain.count >= 4 else { return false }
        for index in 1...(domain.count - 3) where domain[index] == "." {
            return true
        }
        return false
    }

    /// Sign up needs at least `minimumPasswordLength` characters; log in only needs a password to be typed.
    public static func isValidPassword(_ text: String, for mode: AuthMode) -> Bool {
        switch mode {
        case .signUp: return text.count >= minimumPasswordLength
        case .logIn: return !text.isEmpty
        }
    }

    public static func check(email: String, password: String, mode: AuthMode) -> CredentialsCheck {
        CredentialsCheck(
            emailIsValid: isValidEmail(email),
            passwordIsValid: isValidPassword(password, for: mode)
        )
    }
}
