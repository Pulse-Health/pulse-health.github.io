// swift-tools-version: 5.9
import PackageDescription

// PulseBillingKit: Stripe subscriptions for the Pulse iOS app (design: ../../../billing/docs/client-design.md).
//
//   PulseBillingCore  Foundation only: models, API client, entitlement cache, purchase state machine, strings.
//                     Builds and is tested on Linux (swift test).
//   PulseBillingUI    iOS: Stripe PaymentSheet presenter, paywall and manage screens, view model. Every file is wrapped in
//                     `#if os(iOS)`, and the Stripe SDK is only linked on Apple platforms, so the package still resolves
//                     and builds (to an empty UI module) on Linux.

var packageDependencies: [Package.Dependency] = []
var uiDependencies: [Target.Dependency] = ["PulseBillingCore"]

#if !os(Linux)
// Manifest conditions are evaluated for the machine that builds, so this keeps the Stripe SDK out of the Linux CI job.
packageDependencies.append(.package(url: "https://github.com/stripe/stripe-ios-spm", from: "24.0.0"))
uiDependencies.append(.product(name: "StripePaymentSheet", package: "stripe-ios-spm", condition: .when(platforms: [.iOS])))
#endif

let package = Package(
    name: "PulseBillingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PulseBillingCore", targets: ["PulseBillingCore"]),
        .library(name: "PulseBillingUI", targets: ["PulseBillingUI"]),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(name: "PulseBillingCore"),
        .target(name: "PulseBillingUI", dependencies: uiDependencies),
        .testTarget(name: "PulseBillingCoreTests", dependencies: ["PulseBillingCore"]),
    ]
)
