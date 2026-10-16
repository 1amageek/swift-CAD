import CADCore

/// Exact original free-axis endpoints; all published jets keep the original affine image.
struct SurfaceSilhouetteFreeParameterImage: Hashable, Sendable {
    let start: ExactMonotoneGraphEndpoint
    let end: ExactMonotoneGraphEndpoint
    let normalizedDomain: ScalarInterval

    init(start: ExactMonotoneGraphEndpoint, end: ExactMonotoneGraphEndpoint) throws {
        self.start = start; self.end = end
        normalizedDomain = try ScalarInterval(lower: 0, upper: 1)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.start.identityEquals(b.start) && a.end.identityEquals(b.end)
    }
    func hash(into hasher: inout Hasher) {
        start.hashIdentity(into: &hasher); end.hashIdentity(into: &hasher)
    }
    func mapped(over range: ScalarInterval, nativeCover: ScalarInterval,
        usage: inout OriginalQueryExecution) throws -> (parameter: ScalarInterval, derivative: OutwardScalarInterval) {
        let lowerSlope = try end.lower.subtracting(start.upper, usage: &usage)
        let upperSlope = try end.upper.subtracting(start.lower, usage: &usage)
        guard lowerSlope.isPositive else {
            throw rationalAlgebraFailure("Original silhouette affine endpoint image has no exact positive traversal authority.")
        }
        let a = try start.lower.outwardInterval(usage: &usage)
        let b = try start.upper.outwardInterval(usage: &usage)
        let c = try lowerSlope.outwardInterval(usage: &usage)
        let d = try upperSlope.outwardInterval(usage: &usage)
        let slope = OutwardScalarInterval(lower: c.lower, upper: d.upper)
        let first = OutwardScalarInterval(lower: a.lower, upper: b.upper)
        let image: OutwardScalarInterval
        if range.lower == 0, range.upper == 0 { image = first }
        else if range.lower == 1, range.upper == 1 {
            let lower = try end.lower.outwardInterval(usage: &usage)
            let upper = try end.upper.outwardInterval(usage: &usage)
            image = .init(lower: lower.lower, upper: upper.upper)
        } else { image = first + slope * OutwardScalarInterval(lower: range.lower, upper: range.upper) }
        guard let original = image.intersection(with: .init(lower: nativeCover.lower, upper: nativeCover.upper)) else {
            throw rationalAlgebraFailure("Original silhouette affine image missed its certified native rectangle.")
        }
        return try (.init(lower: original.lower, upper: original.upper), slope)
    }
    func refined(usage: inout OriginalQueryExecution) throws -> Self {
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &usage)
        func endpoint(_ value: ExactMonotoneGraphEndpoint) throws -> ExactMonotoneGraphEndpoint {
            let width = try value.upper.subtracting(value.lower, usage: &usage)
            if !width.isPositive { return value }
            return try value.refined(maximumWidth: width.divided(by: two, usage: &usage),
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        let result = try Self(start: endpoint(start), end: endpoint(end))
        guard result != self else {
            throw rationalAlgebraFailure("Original silhouette endpoint image has reached exact source resolution.")
        }
        return result
    }
}
