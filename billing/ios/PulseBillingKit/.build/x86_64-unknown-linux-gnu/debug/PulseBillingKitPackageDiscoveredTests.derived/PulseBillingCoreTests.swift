import XCTest
@testable import PulseBillingCoreTests

fileprivate extension BillingAPITests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__BillingAPITests = [
        ("testA401IsRetriedOnceWithAFreshToken", asyncTest(testA401IsRetriedOnceWithAFreshToken)),
        ("testASecond401BecomesUnauthorizedWithoutAThirdAttempt", asyncTest(testASecond401BecomesUnauthorizedWithoutAThirdAttempt)),
        ("testBaseURLWithAPathPrefixIsKept", asyncTest(testBaseURLWithAPathPrefixIsKept)),
        ("testContractErrorsKeepTheirCodeStatusAndMessage", asyncTest(testContractErrorsKeepTheirCodeStatusAndMessage)),
        ("testCountryIsOmittedWhenUnknownOrMalformed", asyncTest(testCountryIsOmittedWhenUnknownOrMalformed)),
        ("testEntitlementEndpointsUseTheirContractPaths", asyncTest(testEntitlementEndpointsUseTheirContractPaths)),
        ("testNoSessionTokenMeansUnauthorizedAndNothingIsSent", asyncTest(testNoSessionTokenMeansUnauthorizedAndNothingIsSent)),
        ("testOffersRequestAndResponse", asyncTest(testOffersRequestAndResponse)),
        ("testPortalAndAccountDeletion", asyncTest(testPortalAndAccountDeletion)),
        ("testStartSubscriptionSendsTheContractBodyAndIdempotencyKey", asyncTest(testStartSubscriptionSendsTheContractBodyAndIdempotencyKey)),
        ("testTransportFailuresAreNetworkErrorsAndGarbageIsAnInvalidResponse", asyncTest(testTransportFailuresAreNetworkErrorsAndGarbageIsAnInvalidResponse)),
        ("testUnknownErrorCodesAndBodiesThatAreNotJSON", asyncTest(testUnknownErrorCodesAndBodiesThatAreNotJSON))
    ]
}

fileprivate extension ContractTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__ContractTests = [
        ("testEntitlementSurvivesAnEncodeDecodeRoundTrip", testEntitlementSurvivesAnEncodeDecodeRoundTrip),
        ("testEveryFixtureIsCovered", testEveryFixtureIsCovered),
        ("testMalformedDatesAreRejected", testMalformedDatesAreRejected),
        ("testUnknownEnumValuesAndFieldsNeverBreakDecoding", testUnknownEnumValuesAndFieldsNeverBreakDecoding)
    ]
}

fileprivate extension EntitlementCacheTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__EntitlementCacheTests = [
        ("testACorruptEntryReadsAsNothing", testACorruptEntryReadsAsNothing),
        ("testInMemoryCacheIsPerUser", testInMemoryCacheIsPerUser),
        ("testNotPremiumOrNothingCachedIsNotPremium", testNotPremiumOrNothingCachedIsNotPremium),
        ("testPremiumUntilEndsTrustEvenInsideTheWindow", testPremiumUntilEndsTrustEvenInsideTheWindow),
        ("testPremiumWithinTheWindowAndBeforePremiumUntil", testPremiumWithinTheWindowAndBeforePremiumUntil),
        ("testPremiumWithoutPremiumUntilReliesOnTheWindowOnly", testPremiumWithoutPremiumUntilReliesOnTheWindowOnly),
        ("testTheOfflineWindowCapsHowLongAnUnconfirmedAnswerIsTrusted", testTheOfflineWindowCapsHowLongAnUnconfirmedAnswerIsTrusted),
        ("testUserDefaultsCachePersistsAcrossInstancesAndIsPerUser", testUserDefaultsCachePersistsAcrossInstancesAndIsPerUser)
    ]
}

fileprivate extension FormattingTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__FormattingTests = [
        ("testFailuresHaveText", testFailuresHaveText),
        ("testMinorUnitsFollowStripesTable", testMinorUnitsFollowStripesTable),
        ("testPeriodAndTrialWording", testPeriodAndTrialWording),
        ("testPriceOfAPlan", testPriceOfAPlan),
        ("testPricesUseTheCurrencysOwnDecimals", testPricesUseTheCurrencysOwnDecimals),
        ("testStorefrontCodesBecomeTwoLetterCodes", testStorefrontCodesBecomeTwoLetterCodes),
        ("testStringsFollowTheLanguageAndCoverEveryStatus", testStringsFollowTheLanguageAndCoverEveryStatus),
        ("testThePayButtonAlwaysStatesThePaymentObligation", testThePayButtonAlwaysStatesThePaymentObligation)
    ]
}

fileprivate extension PurchaseCoordinatorTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__PurchaseCoordinatorTests = [
        ("testAFailedSheetShowsItsMessage", asyncTest(testAFailedSheetShowsItsMessage)),
        ("testALateWebhookIsWaitedFor", asyncTest(testALateWebhookIsWaitedFor)),
        ("testALostSessionDuringConfirmationStopsTheLoop", asyncTest(testALostSessionDuringConfirmationStopsTheLoop)),
        ("testASecondPurchaseWhileOneRunsIsIgnored", asyncTest(testASecondPurchaseWhileOneRunsIsIgnored)),
        ("testATransientSyncErrorDoesNotTurnAPaymentIntoAnErrorScreen", asyncTest(testATransientSyncErrorDoesNotTurnAPaymentIntoAnErrorScreen)),
        ("testATrialPassesTheSetupIntentToTheSheet", asyncTest(testATrialPassesTheSetupIntentToTheSheet)),
        ("testAlreadySubscribedJustConfirms", asyncTest(testAlreadySubscribedJustConfirms)),
        ("testAvailableButEmptyIsTreatedAsUnavailable", asyncTest(testAvailableButEmptyIsTreatedAsUnavailable)),
        ("testBillingCountryIsForwarded", asyncTest(testBillingCountryIsForwarded)),
        ("testCancelAndResumeUpdateTheCache", asyncTest(testCancelAndResumeUpdateTheCache)),
        ("testClosingTheSheetIsNotAnError", asyncTest(testClosingTheSheetIsNotAnError)),
        ("testEveryPurchaseGetsAFreshIdempotencyKey", asyncTest(testEveryPurchaseGetsAFreshIdempotencyKey)),
        ("testHappyPath", asyncTest(testHappyPath)),
        ("testNoConsentIsSentWhenNotGiven", asyncTest(testNoConsentIsSentWhenNotGiven)),
        ("testNothingToCollectSkipsTheSheet", asyncTest(testNothingToCollectSkipsTheSheet)),
        ("testOffersFailureIsReported", asyncTest(testOffersFailureIsReported)),
        ("testOffersWithPlansAreReady", asyncTest(testOffersWithPlansAreReady)),
        ("testRefreshStoresAnswersButAFailureLeavesTheCacheAlone", asyncTest(testRefreshStoresAnswersButAFailureLeavesTheCacheAlone)),
        ("testServerRefusalsMapToTypedFailures", asyncTest(testServerRefusalsMapToTypedFailures)),
        ("testStillNotPremiumAfterAllAttemptsIsPendingActivation", asyncTest(testStillNotPremiumAfterAllAttemptsIsPendingActivation)),
        ("testTheSellerNameComesFromTheOffersOrTheHostDefault", asyncTest(testTheSellerNameComesFromTheOffersOrTheHostDefault)),
        ("testUnavailableOffersHideTheBuyButton", asyncTest(testUnavailableOffersHideTheBuyButton))
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __PulseBillingCoreTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(BillingAPITests.__allTests__BillingAPITests),
        testCase(ContractTests.__allTests__ContractTests),
        testCase(EntitlementCacheTests.__allTests__EntitlementCacheTests),
        testCase(FormattingTests.__allTests__FormattingTests),
        testCase(PurchaseCoordinatorTests.__allTests__PurchaseCoordinatorTests)
    ]
}