public enum QuantityKind: String, Sendable {
    case length
    case angle
    case scalar
}

public struct Quantity: Hashable, Sendable {
    public var value: Double
    public var kind: QuantityKind

    public init(value: Double, kind: QuantityKind) {
        self.value = value
        self.kind = kind
    }

    public func validate() throws {
        guard value.isFinite else {
            throw UnitError.invalidQuantityValue(value)
        }
    }

    public static func length(_ value: Double, unit: LengthUnit) -> Quantity {
        Quantity(value: unit.toInternal(value), kind: .length)
    }

    public static func angle(_ value: Double, unit: AngleUnit) -> Quantity {
        Quantity(value: unit.toInternal(value), kind: .angle)
    }

    public static func scalar(_ value: Double) -> Quantity {
        Quantity(value: value, kind: .scalar)
    }
}

#if !hasFeature(Embedded)
extension QuantityKind: Codable {}
extension Quantity: Codable {}
#endif
