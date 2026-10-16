import CADCore

/// An exact retained original parameter value; its floating bounds are queries.
public struct SurfaceSilhouetteTrimEndpoint: Sendable {
    let queryContext: SurfaceSilhouetteQueryContext
    let original: OriginalSingularFieldElement
    public let sourceDepth: Int
    private let isolation: OriginalSingularFieldValueIsolation?
    init(_ original: OriginalSingularFieldElement, depth: Int, using execution: inout OriginalQueryExecution) throws {
        queryContext = try .init(retaining: &execution)
        self.original = original; sourceDepth = max(depth, original.context.depth); isolation = nil
    }

    private init(retaining isolation: OriginalSingularFieldValueIsolation, queryContext: SurfaceSilhouetteQueryContext) {
        self.queryContext = queryContext
        original = isolation.original; sourceDepth = isolation.sourceDepth; self.isolation = isolation
    }

    /// Returns the endpoint with persistent exact bounds and actual inherited depth.
    public func refined(maximumWidth: ExactRationalCoefficient,
        using execution: inout OriginalQueryExecution) throws -> Self {
        return try queryContext.withExecution(using: &execution) { execution in
        let retained = try isolation ?? OriginalSingularFieldValueIsolation(original: original,
            inheritedDepth: sourceDepth, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let result = try retained.refined(maximumWidth: maximumWidth,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &execution)
        return Self(retaining: result, queryContext: queryContext)
    
        }
    }

    public func enclosure(maximumWidth: ExactRationalCoefficient,
        using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        return try queryContext.withExecution(using: &execution) { execution in
        let endpoint = try refined(maximumWidth: maximumWidth, using: &execution)
        guard let retained = endpoint.isolation else { throw rationalAlgebraFailure("Original endpoint lost its scalar isolation receipt.") }
        let bounds = try retained.enclosure(usage: &execution)
        return try ScalarInterval(lower: bounds.lower, upper: bounds.upper)
    
        }
    }

    /// Compares source expressions, including roots retained by different owners.
    public func compare(to other: Self, using execution: inout OriginalQueryExecution) throws -> Int {
        return try queryContext.withExecution(using: &execution) { execution in
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(other.original.context, into: original.context,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let first = try original.embedded(in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let second = try transport.applying(to: other.original, in: context,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let difference = try first.subtracting(second, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        var retained = try OriginalSingularFieldValueIsolation(original: difference,
            inheritedDepth: max(sourceDepth, other.sourceDepth), maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        var width = ExactRationalCoefficient.one
        while true {
            if retained.lower.isPositive { return 1 }
            if retained.upper.isNegative { return -1 }
            if retained.lower.isZero, retained.upper.isZero { return 0 }
            retained = try retained.refined(maximumWidth: width, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            width = try width.divided(by: .natural(2, usage: &execution), usage: &execution)
        }
    
        }
    }

    /// A strictly interior original binary fraction, proved by exact comparisons.
    public func interiorWitness(before upper: Self,
        using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        return try queryContext.withExecution(using: &execution) { execution in
        guard try compare(to: upper, using: &execution) < 0 else {
            throw rationalAlgebraFailure("Original trim sector has no positive source parameter interval.")
        }
        var width = ExactRationalCoefficient.one
        var first = self, last = upper
        while true {
            first = try first.refined(maximumWidth: width, using: &execution)
            last = try last.refined(maximumWidth: width, using: &execution)
            guard let a = first.isolation, let b = last.isolation else {
                throw rationalAlgebraFailure("Original trim witness lost retained endpoint bounds.")
            }
            if try b.lower.subtracting(a.upper, usage: &execution).isPositive {
                return try a.upper.adding(b.lower, usage: &execution)
                    .divided(by: .natural(2, usage: &execution), usage: &execution)
            }
            width = try width.divided(by: .natural(2, usage: &execution), usage: &execution)
        }
    
        }
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout OriginalQueryExecution) throws {
        try emitter.emit(.beginRecord(type: "trimEndpoint"), usage: &usage)
        try emitter.field("original", usage: &usage); try emitter.write(original, usage: &usage)
        try emitter.field("sourceDepth", usage: &usage); try emitter.write(sourceDepth, usage: &usage)
        try emitter.field("isolation", usage: &usage)
        if let isolation { try emitter.write(isolation, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.emit(.endRecord, usage: &usage)
    }

}
