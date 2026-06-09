import Foundation

enum ProductSurfacePolicy {
  static let compatibilityAuditLabel = "Compatibility Evidence Audit"
  static let compatibilityRecordsTitle = "Compatibility Records"
  static let noCompatibilityRecords = "No compatibility tournament records are loaded."

  static let retiredMarketPressureMessage =
    "Market-pressure mode is retired. Use model-free or persona-model proof runs; legacy market-pressure evidence remains readable for audit."

  static let marketCompilerPromptVersionID = "market_compiler.pmf_seed_compatibility.v2"
}
