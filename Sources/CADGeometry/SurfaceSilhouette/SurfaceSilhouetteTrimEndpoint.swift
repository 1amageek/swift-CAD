import CADCore

/// An exact retained original parameter value; its floating bounds are queries.
public struct SurfaceSilhouetteTrimEndpoint: Sendable {
    let original: OriginalSingularFieldElement
    public let sourceDepth: Int
    private let isolation: OriginalSingularFieldValueIsolation?
    init(_ original: OriginalSingularFieldElement, depth: Int) {
        self.original = original; sourceDepth = max(depth, original.context.depth); isolation = nil
    }

    private init(retaining isolation: OriginalSingularFieldValueIsolation) {
        original = isolation.original; sourceDepth = isolation.sourceDepth; self.isolation = isolation
    }

    /// Returns the endpoint with persistent exact bounds and actual inherited depth.
    public func refined(maximumWidth: ExactRationalCoefficient,
        usage: inout SurfaceSilhouetteUsage) throws -> Self {
        let retained = try isolation ?? OriginalSingularFieldValueIsolation(original: original,
            inheritedDepth: sourceDepth, maximumDepth: usage.maximumDepth, usage: &usage)
        let result = try retained.refined(maximumWidth: maximumWidth,
            maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(retaining: result)
    }

    public func enclosure(maximumWidth: ExactRationalCoefficient,
        usage: inout SurfaceSilhouetteUsage) throws -> ScalarInterval {
        let endpoint = try refined(maximumWidth: maximumWidth, usage: &usage)
        guard let retained = endpoint.isolation else { throw rationalAlgebraFailure("Original endpoint lost its scalar isolation receipt.") }
        let bounds = try retained.enclosure(usage: &usage)
        return try ScalarInterval(lower: bounds.lower, upper: bounds.upper)
    }

    /// Compares source expressions, including roots retained by different owners.
    public func compare(to other: Self, usage: inout SurfaceSilhouetteUsage) throws -> Int {
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(other.original.context, into: original.context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let first = try original.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let second = try transport.applying(to: other.original, in: context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let difference = try first.subtracting(second, maximumDepth: usage.maximumDepth, usage: &usage)
        var retained = try OriginalSingularFieldValueIsolation(original: difference,
            inheritedDepth: max(sourceDepth, other.sourceDepth), maximumDepth: usage.maximumDepth, usage: &usage)
        var width = ExactRationalCoefficient.one
        while true {
            if retained.lower.isPositive { return 1 }
            if retained.upper.isNegative { return -1 }
            if retained.lower.isZero, retained.upper.isZero { return 0 }
            retained = try retained.refined(maximumWidth: width, maximumDepth: usage.maximumDepth, usage: &usage)
            width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
        }
    }

    /// A strictly interior original binary fraction, proved by exact comparisons.
    public func interiorWitness(before upper: Self,
        usage: inout SurfaceSilhouetteUsage) throws -> ExactRationalCoefficient {
        guard try compare(to: upper, usage: &usage) < 0 else {
            throw rationalAlgebraFailure("Original trim sector has no positive source parameter interval.")
        }
        var width = ExactRationalCoefficient.one
        var first = self, last = upper
        while true {
            first = try first.refined(maximumWidth: width, usage: &usage)
            last = try last.refined(maximumWidth: width, usage: &usage)
            guard let a = first.isolation, let b = last.isolation else {
                throw rationalAlgebraFailure("Original trim witness lost retained endpoint bounds.")
            }
            if try b.lower.subtracting(a.upper, usage: &usage).isPositive {
                return try a.upper.adding(b.lower, usage: &usage)
                    .divided(by: .natural(2, usage: &usage), usage: &usage)
            }
            width = try width.divided(by: .natural(2, usage: &usage), usage: &usage)
        }
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout SurfaceSilhouetteUsage) throws {
        try emitter.emit(.beginRecord(type: "trimEndpoint"), usage: &usage)
        try emitter.field("original", usage: &usage); try emitter.write(original, usage: &usage)
        try emitter.field("sourceDepth", usage: &usage); try emitter.write(sourceDepth, usage: &usage)
        try emitter.field("isolation", usage: &usage)
        if let isolation { try emitter.write(isolation, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.emit(.endRecord, usage: &usage)
    }

}
