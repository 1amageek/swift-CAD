public enum LengthUnit: String, Codable, CaseIterable, Sendable {
    case micrometer
    case meter
    case millimeter
    case centimeter
    case inch
    case foot

    public var metersPerUnit: Double {
        switch self {
        case .micrometer:
            0.000_001
        case .meter:
            1.0
        case .millimeter:
            0.001
        case .centimeter:
            0.01
        case .inch:
            0.0254
        case .foot:
            0.3048
        }
    }

    public func toInternal(_ value: Double) -> Double {
        value * metersPerUnit
    }

    public func fromInternal(_ value: Double) -> Double {
        value / metersPerUnit
    }
}

public enum AngleUnit: String, Codable, CaseIterable, Sendable {
    case radian
    case degree

    public func toInternal(_ value: Double) -> Double {
        switch self {
        case .radian:
            value
        case .degree:
            value * .pi / 180.0
        }
    }

    public func fromInternal(_ value: Double) -> Double {
        switch self {
        case .radian:
            value
        case .degree:
            value * 180.0 / .pi
        }
    }
}

public struct UnitSystem: Codable, Hashable, Sendable {
    public var length: LengthUnit
    public var angle: AngleUnit

    public init(length: LengthUnit, angle: AngleUnit) {
        self.length = length
        self.angle = angle
    }

    public func validate() throws {
        guard length.metersPerUnit.isFinite, length.metersPerUnit > 0.0 else {
            throw UnitError.invalidUnitSystem
        }
        let angleScale = angle.toInternal(1.0)
        guard angleScale.isFinite, angleScale > 0.0 else {
            throw UnitError.invalidUnitSystem
        }
    }

    public static let millimeters = UnitSystem(length: .millimeter, angle: .degree)
    public static let meters = UnitSystem(length: .meter, angle: .radian)
}
