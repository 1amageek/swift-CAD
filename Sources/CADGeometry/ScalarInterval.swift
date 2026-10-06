import CADCore

public struct ScalarInterval: Equatable, Hashable, Sendable {
    public let lower: Double
    public let upper: Double

    public init(lower: Double, upper: Double) throws {
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Scalar interval bounds must be finite and ordered."
            )
        }
        self.lower = lower
        self.upper = upper
    }

    public var width: Double { upper - lower }
    /// A finite representative; source proofs retain outward endpoint arithmetic.
    public var midpoint: Double {
        if lower < 0, upper > 0 { return lower * 0.5 + upper * 0.5 }
        return lower + (upper - lower) * 0.5
    }

    public func contains(_ value: Double) -> Bool {
        lower ... upper ~= value
    }

    public func intersects(_ other: ScalarInterval) -> Bool {
        lower <= other.upper && other.lower <= upper
    }

    public func expanded(by amount: Double) throws -> ScalarInterval {
        guard amount.isFinite, amount >= 0.0 else {
            throw GeometryError.invalidDistance(amount)
        }
        return try ScalarInterval(lower: lower - amount, upper: upper + amount)
    }
}

#if !hasFeature(Embedded)
extension ScalarInterval: Codable {}
#endif
