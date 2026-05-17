import Foundation

struct CinematicInfluenceSettings: Codable, Equatable {
    enum CameraStyle: String, Codable, CaseIterable, Identifiable {
        case steady
        case follow
        case dramatic

        var id: Self { self }

        var title: String {
            switch self {
            case .steady:
                return "Steady"
            case .follow:
                return "Follow"
            case .dramatic:
                return "Dramatic"
            }
        }
    }

    static let defaultIntensity = 0.5
    static let intensityRange = 0.0...1.0

    var cameraStyle: CameraStyle
    var intensity: Double

    init(
        cameraStyle: CameraStyle = .follow,
        intensity: Double = Self.defaultIntensity
    ) {
        self.cameraStyle = cameraStyle
        self.intensity = Self.clampedIntensity(intensity)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCameraStyle = try container.decodeIfPresent(String.self, forKey: .cameraStyle)
        cameraStyle = rawCameraStyle.flatMap(CameraStyle.init(rawValue:)) ?? .follow
        intensity = Self.clampedIntensity(
            try container.decodeIfPresent(Double.self, forKey: .intensity) ?? Self.defaultIntensity
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cameraStyle.rawValue, forKey: .cameraStyle)
        try container.encode(Self.clampedIntensity(intensity), forKey: .intensity)
    }

    static func clampedIntensity(_ value: Double) -> Double {
        min(max(value, intensityRange.lowerBound), intensityRange.upperBound)
    }

    enum CodingKeys: String, CodingKey {
        case cameraStyle
        case intensity
    }
}
