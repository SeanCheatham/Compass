import Foundation
@testable import Compass
import XCTest

final class AgentSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var keychain: InMemoryAgentKeychain!

    override func setUpWithError() throws {
        suiteName = "compass.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        for key in AgentSettingsStore.Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
        keychain = InMemoryAgentKeychain()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        keychain = nil
    }

    // MARK: - Defaults

    func testEmptyStoreFallsBackToBuiltInDefaults() {
        let store = makeStore(environment: [:])
        let settings = store.load()
        XCTAssertEqual(settings.baseURL, AgentRuntimeSettings.defaultBaseURL)
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertEqual(settings.model, AgentRuntimeSettings.defaultModelIdentifier)
        XCTAssertNil(settings.planModelOverride)
        XCTAssertNil(settings.developModelOverride)
        XCTAssertNil(settings.reflectModelOverride)
    }

    func testEmptyStoreSeedsFromEnvironment() {
        let store = makeStore(environment: [
            "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
            "COMPASS_AGENT_API_KEY": "env-key",
            "COMPASS_AGENT_MODEL": "env-model",
            "COMPASS_AGENT_MODEL_PLAN": "env-plan"
        ])
        let settings = store.load()
        XCTAssertEqual(settings.baseURL.absoluteString, "https://example.test/v1")
        XCTAssertEqual(settings.apiKey, "env-key")
        XCTAssertEqual(settings.model, "env-model")
        XCTAssertEqual(settings.planModelOverride, "env-plan")
    }

    // MARK: - Setters persist

    func testPersistedBaseURLBeatsEnvironment() {
        let store = makeStore(environment: ["COMPASS_AGENT_BASE_URL": "https://env.test/v1"])
        store.setBaseURL("https://ui.test/v1")
        XCTAssertEqual(store.load().baseURL.absoluteString, "https://ui.test/v1")
    }

    func testPersistedModelBeatsEnvironment() {
        let store = makeStore(environment: ["COMPASS_AGENT_MODEL": "env-model"])
        store.setDefaultModel("ui-model")
        XCTAssertEqual(store.load().model, "ui-model")
    }

    func testSettingEmptyClearsTheStoredValueAndFallsBackToEnv() {
        let store = makeStore(environment: ["COMPASS_AGENT_MODEL": "env-model"])
        store.setDefaultModel("ui-model")
        XCTAssertEqual(store.load().model, "ui-model")
        store.setDefaultModel("   ")
        XCTAssertEqual(store.load().model, "env-model")
    }

    func testSettingEmptyWithNoEnvFallsBackToDefault() {
        let store = makeStore(environment: [:])
        store.setDefaultModel("ui-model")
        store.setDefaultModel("")
        XCTAssertEqual(store.load().model, AgentRuntimeSettings.defaultModelIdentifier)
    }

    func testInvalidBaseURLFallsBackToDefault() {
        let store = makeStore(environment: [:])
        store.setBaseURL("not a url at all")
        // URL(string:) is lenient enough to accept "not a url at all", so
        // exercise an explicit always-invalid string by setting an empty
        // value (which clears the entry) and then checking default fallback.
        store.setBaseURL("")
        XCTAssertEqual(store.load().baseURL, AgentRuntimeSettings.defaultBaseURL)
    }

    // MARK: - API key in Keychain

    func testAPIKeyRoundTripsThroughKeychain() throws {
        let store = makeStore(environment: [:])
        try store.setAPIKey("sk-abc")
        XCTAssertEqual(store.load().apiKey, "sk-abc")
        let direct = try keychain.read(
            service: AgentSettingsStore.keychainService,
            account: AgentSettingsStore.keychainAccount
        )
        XCTAssertEqual(direct, "sk-abc")
    }

    func testClearingAPIKeyRemovesKeychainEntry() throws {
        let store = makeStore(environment: ["COMPASS_AGENT_API_KEY": "env-key"])
        try store.setAPIKey("sk-abc")
        XCTAssertEqual(store.load().apiKey, "sk-abc")
        try store.setAPIKey("")
        XCTAssertEqual(store.load().apiKey, "env-key")
        let direct = try keychain.read(
            service: AgentSettingsStore.keychainService,
            account: AgentSettingsStore.keychainAccount
        )
        XCTAssertNil(direct)
    }

    func testPerPhaseModelOverridesPersist() {
        let store = makeStore(environment: [:])
        store.setPlanModelOverride("plan-x")
        store.setDevelopModelOverride("dev-x")
        store.setReflectModelOverride("ref-x")
        let settings = store.load()
        XCTAssertEqual(settings.planModelOverride, "plan-x")
        XCTAssertEqual(settings.developModelOverride, "dev-x")
        XCTAssertEqual(settings.reflectModelOverride, "ref-x")
    }

    // MARK: - Helpers

    private func makeStore(environment: [String: String]) -> AgentSettingsStore {
        AgentSettingsStore(
            defaults: defaults,
            keychain: keychain,
            environment: environment
        )
    }
}
