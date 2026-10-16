import CADCore

/// Original retained silhouette traversal between exact trim-event expressions.
public struct OriginalSurfaceSilhouetteTrimmedCurve: Sendable {
    public let original: OriginalSurfaceSilhouetteCurve
    public let lower: SurfaceSilhouetteTrimEndpoint
    public let upper: SurfaceSilhouetteTrimEndpoint
    private let start: OriginalSingularFieldElement
    private let gain: OriginalSingularFieldElement
    private let gainIsolation: OriginalSingularFieldValueIsolation?
    public let sourceDepth: Int

    /// Retains authored original native endpoints; algebraic cuts use the endpoint initializer.
    public init(original: OriginalSurfaceSilhouetteCurve, from: Double, to: Double,
        using execution: inout OriginalQueryExecution) throws {
        self = try original.queryContext.withExecution(using: &execution) { execution in
        guard from.isFinite, to.isFinite, from < to else {
            throw GeometryConversionError.invalidInput("Original native silhouette trim needs finite increasing endpoints.")
        }
        let context = try OriginalSingularFieldContext(usage: &execution)
        let first = try OriginalSingularFieldElement.constant(.originalDouble(from, usage: &execution),
            in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let last = try OriginalSingularFieldElement.constant(.originalDouble(to, usage: &execution),
            in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        try RationalAlgebraStorage.retain(2, of: SurfaceSilhouetteTrimEndpoint.self, usage: &execution)
        return try Self(original: original, lower: .init(first, depth: 0, using: &execution),
            upper: try .init(last, depth: 0, using: &execution), using: &execution)
    
        }
    }

    public init(original: OriginalSurfaceSilhouetteCurve, lower: SurfaceSilhouetteTrimEndpoint,
        upper: SurfaceSilhouetteTrimEndpoint, using execution: inout OriginalQueryExecution) throws {
        self = try original.queryContext.withExecution(using: &execution) { execution in
            try Self(admittedOriginal: original, lower: lower, upper: upper, using: &execution)
        }
    }

    private init(admittedOriginal original: OriginalSurfaceSilhouetteCurve, lower: SurfaceSilhouetteTrimEndpoint,
        upper: SurfaceSilhouetteTrimEndpoint, using execution: inout OriginalQueryExecution) throws {
        guard try lower.compare(to: upper, using: &execution) < 0 else {
            throw rationalAlgebraFailure("Original trimmed silhouette requires strictly ordered native endpoints.")
        }
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(upper.original.context, into: lower.original.context,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let start = try lower.original.embedded(in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let end = try transport.applying(to: upper.original, in: context,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let domainLow = try OriginalSingularFieldElement.constant(.originalDouble(original.nativeDomain.lower, usage: &execution),
            in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let domainHigh = try OriginalSingularFieldElement.constant(.originalDouble(original.nativeDomain.upper, usage: &execution),
            in: context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        if case .negative = try start.subtracting(domainLow, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) {
            throw rationalAlgebraFailure("Original trim endpoint precedes the retained silhouette source domain.")
        }
        if case .positive = try end.subtracting(domainHigh, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            .sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) {
            throw rationalAlgebraFailure("Original trim endpoint exceeds the retained silhouette source domain.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &execution)
        self.original = original; self.lower = lower; self.upper = upper; self.start = start
        gain = try end.subtracting(start, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        gainIsolation = nil
        sourceDepth = max(context.depth, max(lower.sourceDepth, upper.sourceDepth))
    }

    private init(copy source: Self, lower: SurfaceSilhouetteTrimEndpoint,
        upper: SurfaceSilhouetteTrimEndpoint, gainIsolation: OriginalSingularFieldValueIsolation) {
        original = source.original; self.lower = lower; self.upper = upper
        start = source.start; gain = source.gain; self.gainIsolation = gainIsolation
        sourceDepth = max(gainIsolation.sourceDepth, max(lower.sourceDepth, upper.sourceDepth))
    }

    /// Continues endpoint and slope proofs; no source transport or normalization is replayed.
    public func refined(maximumParameterWidth: ExactRationalCoefficient,
        using execution: inout OriginalQueryExecution) throws -> Self {
        return try original.queryContext.withExecution(using: &execution) { execution in
        let first = try lower.refined(maximumWidth: maximumParameterWidth, using: &execution)
        let last = try upper.refined(maximumWidth: maximumParameterWidth, using: &execution)
        let retained = try gainIsolation ?? OriginalSingularFieldValueIsolation(original: gain,
            inheritedDepth: max(sourceDepth, max(first.sourceDepth, last.sourceDepth)),
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let inherited = try retained.inheriting(depth: max(first.sourceDepth, last.sourceDepth),
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let slope = try inherited.refined(maximumWidth: maximumParameterWidth,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &execution)
        return Self(copy: self, lower: first, upper: last, gainIsolation: slope)
    
        }
    }

    public func enclosure(overNormalized range: ScalarInterval,
        maximumParameterWidth: ExactRationalCoefficient,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSilhouetteCurveEnclosure {
        return try original.queryContext.withExecution(using: &execution) { execution in
        guard range.lower >= 0, range.upper <= 1, maximumParameterWidth.isPositive else {
            throw rationalAlgebraFailure("Original trimmed silhouette query requires contained fractions and positive source precision.")
        }
        func native(_ parameter: Double) throws -> OutwardScalarInterval {
            if parameter == 0 || parameter == 1 {
                let endpoint = parameter == 0 ? lower : upper
                let bounds = try endpoint.enclosure(maximumWidth: maximumParameterWidth, using: &execution)
                return OutwardScalarInterval(lower: bounds.lower, upper: bounds.upper)
            }
            let t = try OriginalSingularFieldElement.constant(.originalDouble(parameter, usage: &execution),
                in: start.context, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            let value = try start.adding(gain.multiplied(by: t, maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution),
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
            return try value.enclosure(maximumWidth: maximumParameterWidth, inheritedDepth: sourceDepth,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        }
        let first = try native(range.lower), last = try native(range.upper)
        let query = try ScalarInterval(lower: max(original.nativeDomain.lower, first.lower),
            upper: min(original.nativeDomain.upper, last.upper))
        let source = try original.enclosure(over: query, using: &execution)
        let slope: OutwardScalarInterval
        if let gainIsolation {
            slope = try gainIsolation.refined(maximumWidth: maximumParameterWidth,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution).enclosure(usage: &execution)
        } else {
            slope = try gain.enclosure(maximumWidth: maximumParameterWidth, inheritedDepth: sourceDepth,
                maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        }
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw rationalAlgebraFailure("Original trimmed derivative has nonfinite bounds.") }
            return try .init(lower: value.lower, upper: value.upper)
        }
        func scaled(_ value: ScalarInterval, by factor: OutwardScalarInterval) throws -> ScalarInterval {
            try interval(OutwardScalarInterval(lower: value.lower, upper: value.upper) * factor)
        }
        guard source.parameterDerivatives.count == 4, source.spatialDerivatives.count == 4 else {
            throw rationalAlgebraFailure("Original silhouette source did not retain complete D0-D3 derivatives.")
        }
        try RationalAlgebraStorage.retain(4, of: CoordinateEnclosure2D.self, usage: &execution)
        try RationalAlgebraStorage.retain(4, of: CoordinateEnclosure3D.self, usage: &execution)
        var uv: [CoordinateEnclosure2D] = [], xyz: [CoordinateEnclosure3D] = []
        uv.reserveCapacity(4); xyz.reserveCapacity(4)
        var factor = OutwardScalarInterval.exact(1)
        for order in 0..<4 {
            if order > 0 { factor = factor * slope }
            let a = source.parameterDerivatives[order], b = source.spatialDerivatives[order]
            uv.append(try .init(x: scaled(a.x, by: factor), y: scaled(a.y, by: factor)))
            xyz.append(try .init(x: scaled(b.x, by: factor), y: scaled(b.y, by: factor), z: scaled(b.z, by: factor)))
        }
        return .init(parameters: source.parameters, parameterDerivatives: uv, spatialDerivatives: xyz)
    
        }
    }
    /// Visits complete original branch and exact endpoint authority without replaying solvers.
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        using execution: inout OriginalQueryExecution) throws {
        try original.queryContext.withExecution(using: &execution) { execution in
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.emit(.beginRecord(type: "original-surface-silhouette-v1"), usage: &execution)
        try emitter.field("original", usage: &execution)
        try original.writeOriginalProvenance(to: &emitter, usage: &execution)
        try emitter.field("lower", usage: &execution); try lower.writeOriginalProvenance(to: &emitter, usage: &execution)
        try emitter.field("upper", usage: &execution); try upper.writeOriginalProvenance(to: &emitter, usage: &execution)
        try emitter.field("start", usage: &execution); try emitter.write(start, usage: &execution)
        try emitter.field("gain", usage: &execution); try emitter.write(gain, usage: &execution)
        try emitter.field("gainIsolation", usage: &execution)
        if let gainIsolation { try emitter.write(gainIsolation, usage: &execution) }
        else { try emitter.emit(.null, usage: &execution) }
        try emitter.field("sourceDepth", usage: &execution); try emitter.write(sourceDepth, usage: &execution)
        try emitter.emit(.endRecord, usage: &execution)
    
        }
    }

}
