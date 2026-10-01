import CADCore

/// Fillet Shell's limit points: the stretch of a blended edge, as fractions of its length from its
/// start, that the blend runs over; outside it the edge stays sharp and each limit inside the edge
/// closes the blend on its cross-section.
public struct EdgeBlendLimits: Codable, Hashable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public func validate() throws {
        guard start.isFinite, end.isFinite, start >= 0, end <= 1, start < end, start > 0 || end < 1 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                              message: "A blend's limits lie within its edge, 0 ≤ start < end ≤ 1, and limit it somewhere.")
        }
    }
}
