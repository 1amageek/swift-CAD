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
        usage: inout SurfaceSilhouetteUsage) throws {
        guard from.isFinite, to.isFinite, from < to else {
            throw GeometryConversionError.invalidInput("Original native silhouette trim needs finite increasing endpoints.")
        }
        let context = try OriginalSingularFieldContext(usage: &usage)
        let first = try OriginalSingularFieldElement.constant(.originalDouble(from, usage: &usage),
            in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let last = try OriginalSingularFieldElement.constant(.originalDouble(to, usage: &usage),
            in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
        try self.init(original: original, lower: .init(first, depth: 0),
            upper: .init(last, depth: 0), usage: &usage)
    }

    public init(original: OriginalSurfaceSilhouetteCurve, lower: SurfaceSilhouetteTrimEndpoint,
        upper: SurfaceSilhouetteTrimEndpoint, usage: inout SurfaceSilhouetteUsage) throws {
        guard try lower.compare(to: upper, usage: &usage) < 0 else {
            throw rationalAlgebraFailure("Original trimmed silhouette requires strictly ordered native endpoints.")
        }
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(upper.original.context, into: lower.original.context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let start = try lower.original.embedded(in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let end = try transport.applying(to: upper.original, in: context,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let domainLow = try OriginalSingularFieldElement.constant(.originalDouble(original.nativeDomain.lower, usage: &usage),
            in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        let domainHigh = try OriginalSingularFieldElement.constant(.originalDouble(original.nativeDomain.upper, usage: &usage),
            in: context, maximumDepth: usage.maximumDepth, usage: &usage)
        if case .negative = try start.subtracting(domainLow, maximumDepth: usage.maximumDepth, usage: &usage)
            .sign(maximumDepth: usage.maximumDepth, usage: &usage) {
            throw rationalAlgebraFailure("Original trim endpoint precedes the retained silhouette source domain.")
        }
        if case .positive = try end.subtracting(domainHigh, maximumDepth: usage.maximumDepth, usage: &usage)
            .sign(maximumDepth: usage.maximumDepth, usage: &usage) {
            throw rationalAlgebraFailure("Original trim endpoint exceeds the retained silhouette source domain.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        self.original = original; self.lower = lower; self.upper = upper; self.start = start
        gain = try end.subtracting(start, maximumDepth: usage.maximumDepth, usage: &usage)
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
        usage: inout SurfaceSilhouetteUsage) throws -> Self {
        let first = try lower.refined(maximumWidth: maximumParameterWidth, usage: &usage)
        let last = try upper.refined(maximumWidth: maximumParameterWidth, usage: &usage)
        let retained = try gainIsolation ?? OriginalSingularFieldValueIsolation(original: gain,
            inheritedDepth: max(sourceDepth, max(first.sourceDepth, last.sourceDepth)),
            maximumDepth: usage.maximumDepth, usage: &usage)
        let inherited = try retained.inheriting(depth: max(first.sourceDepth, last.sourceDepth),
            maximumDepth: usage.maximumDepth, usage: &usage)
        let slope = try inherited.refined(maximumWidth: maximumParameterWidth,
            maximumDepth: usage.maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(copy: self, lower: first, upper: last, gainIsolation: slope)
    }

    public func enclosure(overNormalized range: ScalarInterval,
        maximumParameterWidth: ExactRationalCoefficient,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteCurveEnclosure {
        guard range.lower >= 0, range.upper <= 1, maximumParameterWidth.isPositive else {
            throw rationalAlgebraFailure("Original trimmed silhouette query requires contained fractions and positive source precision.")
        }
        func native(_ parameter: Double) throws -> OutwardScalarInterval {
            if parameter == 0 || parameter == 1 {
                let endpoint = parameter == 0 ? lower : upper
                let bounds = try endpoint.enclosure(maximumWidth: maximumParameterWidth, usage: &usage)
                return OutwardScalarInterval(lower: bounds.lower, upper: bounds.upper)
            }
            let t = try OriginalSingularFieldElement.constant(.originalDouble(parameter, usage: &usage),
                in: start.context, maximumDepth: usage.maximumDepth, usage: &usage)
            let value = try start.adding(gain.multiplied(by: t, maximumDepth: usage.maximumDepth, usage: &usage),
                maximumDepth: usage.maximumDepth, usage: &usage)
            return try value.enclosure(maximumWidth: maximumParameterWidth, inheritedDepth: sourceDepth,
                maximumDepth: usage.maximumDepth, usage: &usage)
        }
        let first = try native(range.lower), last = try native(range.upper)
        let query = try ScalarInterval(lower: max(original.nativeDomain.lower, first.lower),
            upper: min(original.nativeDomain.upper, last.upper))
        let source = try original.enclosure(over: query, usage: &usage)
        let slope: OutwardScalarInterval
        if let gainIsolation {
            slope = try gainIsolation.refined(maximumWidth: maximumParameterWidth,
                maximumDepth: usage.maximumDepth, usage: &usage).enclosure(usage: &usage)
        } else {
            slope = try gain.enclosure(maximumWidth: maximumParameterWidth, inheritedDepth: sourceDepth,
                maximumDepth: usage.maximumDepth, usage: &usage)
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
        try RationalAlgebraStorage.retain(4, of: CoordinateEnclosure2D.self, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: CoordinateEnclosure3D.self, usage: &usage)
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
    /// Visits complete original branch and exact endpoint authority without replaying solvers.
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        usage: inout SurfaceSilhouetteUsage) throws {
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.emit(.beginRecord(type: "original-surface-silhouette-v1"), usage: &usage)
        try emitter.field("original", usage: &usage)
        try original.writeOriginalProvenance(to: &emitter, usage: &usage)
        try emitter.field("lower", usage: &usage); try lower.writeOriginalProvenance(to: &emitter, usage: &usage)
        try emitter.field("upper", usage: &usage); try upper.writeOriginalProvenance(to: &emitter, usage: &usage)
        try emitter.field("start", usage: &usage); try emitter.write(start, usage: &usage)
        try emitter.field("gain", usage: &usage); try emitter.write(gain, usage: &usage)
        try emitter.field("gainIsolation", usage: &usage)
        if let gainIsolation { try emitter.write(gainIsolation, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("sourceDepth", usage: &usage); try emitter.write(sourceDepth, usage: &usage)
        try emitter.emit(.endRecord, usage: &usage)
    }

}
