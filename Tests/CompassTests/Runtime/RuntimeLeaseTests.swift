import Foundation
import Testing

@testable import Compass
@testable import CompassCore

@Suite("Runtime readiness")
struct RuntimeLeaseTests {
  @Test
  func hybridRuntimeReadiness() {
    let cloud = AgentRuntimeSettings(
      textProvider: .openAICompatible,
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "sk-test",
      model: "example-model"
    )
    #expect(cloud.textProvider == .openAICompatible)
    #expect(cloud.textProvider.requiresCredentials == true)
    #expect(AgentCapability.allCases == [.text])
    #expect(AgentProviderKind.allCases == [.openAICompatible, .mlx])
    #expect(cloud.model(for: .plan) == "example-model")
    #expect(cloud.isTextCapabilityRunnable(localModelReady: false))
    #expect(cloud.isTextCapabilityRunnable(localModelReady: true))
    #expect(cloud.hasCloudCredentials)

    let local = AgentRuntimeSettings(textProvider: .mlx)
    #expect(local.textProvider == .mlx)
    #expect(local.textProvider.requiresCredentials == false)
    #expect(local.model(for: .plan) == LocalModelCatalog.blessedModelID)
    #expect(local.isTextCapabilityRunnable(localModelReady: true))
    #expect(!local.isTextCapabilityRunnable(localModelReady: false))
  }
  @Test
  func localModelLeaseAllowsOneLoadedModelAndUnloadsAfterIdle() async throws {
    await LocalModelLease.shared.resetForTesting()
    await LocalModelLease.shared.setIdleTimeoutForTesting(seconds: 0.01)
    try await LocalModelLease.shared.beginRun(modelID: "model-a")
    await #expect(throws: LocalModelRuntimeError.self) {
      try await LocalModelLease.shared.beginRun(modelID: "model-b")
    }
    await LocalModelLease.shared.endRun(modelID: "model-a")
    var snapshot = await LocalModelLease.shared.snapshot()
    let deadline = Date().addingTimeInterval(1)
    while snapshot.loadedModelID != nil, Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
      snapshot = await LocalModelLease.shared.snapshot()
    }
    #expect(snapshot.loadedModelID == nil)
    #expect(snapshot.activeRunCount == 0)
    await LocalModelLease.shared.resetForTesting()
  }
  @Test
  func localModelCatalogMissingAndReadyStates() throws {
    let missingURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: missingURL) }
    LocalModelCatalog.withTestingModelDirectory(missingURL) {
      #expect(!LocalModelCatalog.isBlessedModelReady())
      #expect(LocalModelCatalog.snapshot().status == .missing)
    }

    let readyURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: readyURL) }
    try "{}".write(to: readyURL.appending(path: "config.json"), atomically: true, encoding: .utf8)
    try "{}".write(
      to: readyURL.appending(path: "tokenizer.json"), atomically: true, encoding: .utf8)
    try Data([0]).write(to: readyURL.appending(path: "model.safetensors"))
    LocalModelCatalog.withTestingModelDirectory(readyURL) {
      #expect(LocalModelCatalog.isBlessedModelReady())
      #expect(LocalModelCatalog.snapshot().status == .ready)
    }
  }
}
