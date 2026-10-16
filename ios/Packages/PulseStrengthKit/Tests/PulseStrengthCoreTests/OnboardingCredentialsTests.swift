import XCTest
@testable import PulseStrengthCore

/// The client-side checks of the account form (OnboardingValidation.swift).
final class OnboardingCredentialsTests: XCTestCase {
    func testAcceptsOrdinaryEmailAddresses() {
        let valid = [
            "robin@example.com",
            "a@b.co",
            "name.surname+tag@example.com",
            "a@b.c.d",
            "x@mail.example.de",
            "  robin@example.com  ",
            "ünï@exämple.de",
        ]
        for address in valid {
            XCTAssertTrue(CredentialsValidator.isValidEmail(address), address)
        }
    }

    func testRejectsAddressesThatCannotBeRight() {
        let invalid = [
            "",
            "   ",
            "robin",
            "robin@",
            "@example.com",
            "robin@example",
            "robin@example.c",
            "robin@.com",
            "robin@@example.com",
            "robin@exa@mple.com",
            "ro bin@example.com",
            "robin@exam ple.com",
            "robin@example.c om",
        ]
        for address in invalid {
            XCTAssertFalse(CredentialsValidator.isValidEmail(address), address)
        }
    }

    func testANewPasswordNeedsEightCharacters() {
        XCTAssertEqual(CredentialsValidator.minimumPasswordLength, 8)
        XCTAssertFalse(CredentialsValidator.isValidPassword("", for: .signUp))
        XCTAssertFalse(CredentialsValidator.isValidPassword("1234567", for: .signUp))
        XCTAssertTrue(CredentialsValidator.isValidPassword("12345678", for: .signUp))
        XCTAssertTrue(CredentialsValidator.isValidPassword("a long passphrase", for: .signUp))
        XCTAssertFalse(CredentialsValidator.isValidPassword("äöü", for: .signUp), "counts characters, not bytes")
        XCTAssertTrue(CredentialsValidator.isValidPassword("ääääääää", for: .signUp))
    }

    func testLoggingInOnlyNeedsAPassword() {
        XCTAssertFalse(CredentialsValidator.isValidPassword("", for: .logIn))
        XCTAssertTrue(CredentialsValidator.isValidPassword("x", for: .logIn), "an old account may have a short password")
    }

    func testCheckReportsEachFieldSeparately() {
        let both = CredentialsValidator.check(email: "a@b.co", password: "12345678", mode: .signUp)
        XCTAssertTrue(both.isValid)

        let badEmail = CredentialsValidator.check(email: "nope", password: "12345678", mode: .signUp)
        XCTAssertFalse(badEmail.emailIsValid)
        XCTAssertTrue(badEmail.passwordIsValid)
        XCTAssertFalse(badEmail.isValid)

        let shortPassword = CredentialsValidator.check(email: "a@b.co", password: "short", mode: .signUp)
        XCTAssertTrue(shortPassword.emailIsValid)
        XCTAssertFalse(shortPassword.passwordIsValid)

        let sameInLogIn = CredentialsValidator.check(email: "a@b.co", password: "short", mode: .logIn)
        XCTAssertTrue(sameInLogIn.isValid)
    }
}
