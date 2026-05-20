import Foundation
@testable import Compass
import XCTest

final class AgentRuntimeSettingsTests: XCTestCase {
    func testDefaultsFromEmptyEnvironmentPointAtMiniMax() {
        let settings = AgentRuntimeSettings.defaultFromEnvironment([:])
        XCTAssertEqual(settings.baseURL.absoluteString, "https://api.minimax.io/v1")
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertEqual(settings.model, "MiniMax-M2.7")
        XCTAssertNil(settings.planModelOverride)
        XCTAssertNil(settings.developModelOverride)
        XCTAssertNil(settings.reflectModelOverride)
    }

    func testEnvironmentOverridesAreApplied() {
        let settings = AgentRuntimeSettings.defaultFromEnvironment([
            "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
            "COMPASS_AGENT_API_KEY": "sk-abc",
            "COMPASS_AGENT_MODEL": "gpt-test",
            "COMPASS_AGENT_MODEL_PLAN": "plan-model",
            "COMPASS_AGENT_MODEL_DEV": "dev-model",
            "COMPASS_AGENT_MODEL_REFLECT": "reflect-model"
        ])

        XCTAssertEqual(settings.baseURL.absoluteString, "https://example.test/v1")
        XCTAssertEqual(settings.apiKey, "sk-abc")
        XCTAssertEqual(settings.model, "gpt-test")
        XCTAssertEqual(settings.planModelOverride, "plan-model")
        XCTAssertEqual(settings.developModelOverride, "dev-model")
        XCTAssertEqual(settings.reflectModelOverride, "reflect-model")
    }

    func testWhitespaceOnlyEnvironmentValuesAreTreatedAsUnset() {
        let settings = AgentRuntimeSettings.defaultFromEnvironment([
            "COMPASS_AGENT_BASE_URL": "   ",
            "COMPASS_AGENT_API_KEY": "\t\n",
            "COMPASS_AGENT_MODEL": "",
            "COMPASS_AGENT_MODEL_PLAN": "   "
        ])

        XCTAssertEqual(settings.baseURL, AgentRuntimeSettings.defaultBaseURL)
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertEqual(settings.model, "MiniMax-M2.7")
        XCTAssertNil(settings.planModelOverride)
    }

    func testInvalidBaseURLFallsBackToDefault() {
        let settings = AgentRuntimeSettings.defaultFromEnvironment([
            "COMPASS_AGENT_BASE_URL": ""
        ])
        XCTAssertEqual(settings.baseURL, AgentRuntimeSettings.defaultBaseURL)
    }

    func testModelForPhaseUsesDefaultWhenNoOverrides() {
        let settings = AgentRuntimeSettings(model: "default-model")
        XCTAssertEqual(settings.model(for: .plan), "default-model")
        XCTAssertEqual(settings.model(for: .develop), "default-model")
        XCTAssertEqual(settings.model(for: .reflect), "default-model")
    }

    func testModelForPhaseUsesPhaseOverrideOverDefault() {
        let settings = AgentRuntimeSettings(
            model: "default-model",
            planModelOverride: "plan-model",
            developModelOverride: "dev-model",
            reflectModelOverride: "reflect-model"
        )
        XCTAssertEqual(settings.model(for: .plan), "plan-model")
        XCTAssertEqual(settings.model(for: .develop), "dev-model")
        XCTAssertEqual(settings.model(for: .reflect), "reflect-model")
    }

    func testSidebarOverrideBeatsPhaseAndDefault() {
        let settings = AgentRuntimeSettings(
            model: "default-model",
            planModelOverride: "plan-model"
        )
        XCTAssertEqual(settings.model(for: .plan, sidebarOverride: "sidebar-model"), "sidebar-model")
        XCTAssertEqual(settings.model(for: .develop, sidebarOverride: "sidebar-model"), "sidebar-model")
    }

    func testWhitespaceSidebarOverrideIsIgnored() {
        let settings = AgentRuntimeSettings(
            model: "default-model",
            planModelOverride: "plan-model"
        )
        XCTAssertEqual(settings.model(for: .plan, sidebarOverride: "   "), "plan-model")
        XCTAssertEqual(settings.model(for: .develop, sidebarOverride: "\n"), "default-model")
    }
}
