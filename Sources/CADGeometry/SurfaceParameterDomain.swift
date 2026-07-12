import CADCore

public enum SurfaceParameterDomain: Codable, Equatable, Hashable, Sendable {
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
                    message: "Bounded surface parameter domains must be finite."
                )
            }
        case let .periodic(period):
            guard period.isFinite, period > 0.0 else {
                throw GeometryError.invalidDistance(period)
            }
        }
    }

    public func contains(_ value: Double, tolerance: Double = 0.0) -> Bool {
        guard value.isFinite, tolerance.isFinite, tolerance >= 0.0 else { return false }
        switch self {
        case .unbounded, .periodic:
            return true
        case let .bounded(lower, upper):
            return value >= lower - tolerance && value <= upper + tolerance
        }
    }
}
