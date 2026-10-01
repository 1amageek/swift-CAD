import CADCore

/// Fillet Shell's limit points: the stretch of a blended edge, as fractions of its length from its
/// start, that the blend runs over; outside it the edge stays sharp and each limit inside the edge
/// closes the blend on its cross-section. Reversed (a limit point clicked), the blend runs over the
/// rest of the edge instead: from its start to `start` and from `end` to its end.
public struct EdgeBlendLimits: Codable, Hashable, Sendable {
    public let start: Double
    public let end: Double
    public let reversed: Bool

    public init(start: Double, end: Double, reversed: Bool = false) {
        self.start = start
        self.end = end
        self.reversed = reversed
    }

    /// The stretches of the edge the blend runs over, in order along it.
    public var stretches: [(start: Double, end: Double)] {
        guard reversed else { return [(start, end)] }
        return [(0, start), (end, 1)].filter { $0.1 > $0.0 }
    }

    public func validate() throws {
        guard start.isFinite, end.isFinite, start >= 0, end <= 1, start < end, start > 0 || end < 1 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                              message: "A blend's limits lie within its edge, 0 ≤ start < end ≤ 1, and limit it somewhere.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case reversed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        reversed = try container.decodeIfPresent(Bool.self, forKey: .reversed) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        if reversed { try container.encode(true, forKey: .reversed) }
    }
}
