import CADCore

public enum CurveParameterDomain: Codable, Equatable, Hashable, Sendable {
    case unbounded
    case bounded(lower: Double, upper: Double)
    case periodic(period: Double)

    public func validate() throws {
        switch self {
        case .unbounded:
            return
        case let .bounded(lower, upper):
            guard lower.isFinite, upper.isFinite, lower <= upper else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: nil,
                    message: "Bounded curve parameter domains must be finite and ordered."
                )
            }
        case let .periodic(period):
            guard period.isFinite, period > 0.0 else {
                throw GeometryError.invalidDistance(period)
            }
        }
    }

    public func contains(_ value: Double, tolerance: Double) -> Bool {
        guard value.isFinite, tolerance.isFinite, tolerance >= 0.0 else { return false }
        switch self {
        case .unbounded, .periodic:
            return true
        case let .bounded(lower, upper):
            return value >= lower - tolerance && value <= upper + tolerance
        }
    }
}
