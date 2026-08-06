import Foundation

/// Optional product surfaces layered on a required Rust `crates/core`.
///
/// Every generated project must include at least one product. iOS is reserved
/// for a later experiment.
public enum GeneratedProduct: String, Codable, Equatable, Sendable, CaseIterable {
  case cli
  case macos
  case server
}

public enum GeneratedProducts {
  public static let `default`: [GeneratedProduct] = [.cli, .macos]

  /// Deduplicate while preserving declaration order; empty input becomes `default`.
  public static func normalize(_ products: [GeneratedProduct]) -> [GeneratedProduct] {
    var seen = Set<GeneratedProduct>()
    var ordered: [GeneratedProduct] = []
    for product in products {
      guard seen.insert(product).inserted else { continue }
      ordered.append(product)
    }
    return ordered.isEmpty ? `default` : ordered
  }

  public static func validate(_ products: [GeneratedProduct]) -> String? {
    if products.isEmpty {
      return "Generated projects require at least one product (`cli`, `macos`, and/or `server`)."
    }
    return nil
  }

  public static func parse(_ rawValues: [String]) throws -> [GeneratedProduct] {
    var parsed: [GeneratedProduct] = []
    for raw in rawValues {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard let product = GeneratedProduct(rawValue: trimmed) else {
        throw GeneratedProductError.unknownProduct(raw)
      }
      parsed.append(product)
    }
    let normalized = normalize(parsed)
    if let error = validate(normalized) {
      throw GeneratedProductError.invalid(error)
    }
    return normalized
  }

  public static func contains(_ products: [GeneratedProduct], _ product: GeneratedProduct) -> Bool {
    normalize(products).contains(product)
  }

  public static func summary(_ products: [GeneratedProduct]) -> String {
    normalize(products).map(\.rawValue).joined(separator: "+")
  }
}

public enum GeneratedProductError: Error, LocalizedError, Equatable {
  case unknownProduct(String)
  case invalid(String)

  public var errorDescription: String? {
    switch self {
    case .unknownProduct(let raw):
      return "Unknown product `\(raw)`. Expected `cli`, `macos`, or `server`."
    case .invalid(let message):
      return message
    }
  }
}
