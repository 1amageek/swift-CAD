import CADCore

/// Original regular strict-transform traversal with exact clipping endpoints.
struct SurfaceSilhouetteRamifiedParameterImage: Hashable, Sendable {
    enum Identity: Hashable, Sendable {
        case rational(OriginalSingularChartIdentity)
        case field(SurfaceSilhouetteFieldChartIdentity)
    }
    let identity: Identity
    let original: OriginalSingularRegularChart
    let sourceDomain: SurfaceParameterBox
    let start: OriginalSingularFieldEndpoint
    let end: OriginalSingularFieldEndpoint
    let retainedStart: OriginalSingularFieldElement?
    let retainedEnd: OriginalSingularFieldElement?
    let originAtUpperEnd: Bool?
    let normalizedDomain: ScalarInterval
    let coefficientWidth: ExactRationalCoefficient
    let refinementDepth: Int

    init(resolution: OriginalSingularResolution, germOrdinal: Int,
        clip: OriginalSingularRegularChartClip, spanOrdinal: Int, usage: inout OriginalQueryExecution) throws {
        identity = try .rational(.init(resolution: resolution, germOrdinal: germOrdinal, clip: clip,
            spanOrdinal: spanOrdinal, usage: &usage))
        original = clip.chart; sourceDomain = clip.sourceDomain
        let span = clip.spans[spanOrdinal]
        var first = clip.stations[span.lowerStation].endpoint, last = clip.stations[span.upperStation].endpoint
        _ = try OriginalSingularFieldEndpoint.between(&first, &last, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        start = first; end = last; retainedStart = nil; retainedEnd = nil; originAtUpperEnd = nil; coefficientWidth = .one
        refinementDepth = max(original.sourceDepth, max(first.depth, last.depth))
        normalizedDomain = try .init(lower: 0, upper: 1)
    }
    init(resolution: OriginalSingularResolution, attachment: OriginalSingularHalfBranchAttachment,
        chart: OriginalSingularRegularChart, sourceDomain: SurfaceParameterBox,
        usage: inout OriginalQueryExecution) throws {
        identity = try .rational(.init(resolution: resolution, germOrdinal: attachment.chartIndex,
            attachment: attachment, chart: chart, sourceDomain: sourceDomain, usage: &usage))
        original = chart; self.sourceDomain = sourceDomain
        let point = attachment.originalLocalPoint
        let free = chart.freeAlongU ? point.localU : point.localV
        let zero = try OriginalSingularFieldElement.constant(.zero, in: free.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        switch try free.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
        case .zero: throw rationalAlgebraFailure("Original nonexceptional half-branch has no positive local traversal.")
        case .positive: retainedStart = zero; retainedEnd = free; originAtUpperEnd = false
        case .negative: retainedStart = free; retainedEnd = zero; originAtUpperEnd = true
        }
        start = .authored(.zero); end = .authored(.zero)
        coefficientWidth = .one; refinementDepth = max(chart.sourceDepth, attachment.approachDepth)
        normalizedDomain = try .init(lower: 0, upper: 1)
    }
    init(resolution: OriginalFieldSingularResolution, attachment: OriginalFieldHalfBranchAttachment,
        chart: OriginalSingularRegularChart, sourceDomain: SurfaceParameterBox,
        usage: inout OriginalQueryExecution) throws {
        guard attachment.chartIndex >= 0, attachment.chartIndex < resolution.germs.count,
            resolution.germs[attachment.chartIndex].strictTransform.context === chart.germ.strictTransform.context else {
            throw rationalAlgebraFailure("Original field half-chart lost its issued resolution leaf.")
        }
        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteFieldChartIdentity.self, usage: &usage)
        identity = .field(.init(owner: chart.germ.strictTransform.context, localDomain: chart.localDomain,
            sourceDomain: sourceDomain, germOrdinal: attachment.chartIndex,
            sectorOrdinal: attachment.halfBranch.sectorIndex, branchOrdinal: attachment.halfBranch.branchOrdinal,
            upperSide: attachment.halfBranch.side == .upperStation, anchor: attachment.originalFreeWitness))
        original = chart; self.sourceDomain = sourceDomain
        let point = attachment.originalLocalPoint
        let free = chart.freeAlongU ? point.localU : point.localV
        let zero = try OriginalSingularFieldElement.constant(.zero, in: free.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        switch try free.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
        case .zero: throw rationalAlgebraFailure("Original field half-chart has no positive traversal.")
        case .positive: retainedStart = zero; retainedEnd = free; originAtUpperEnd = false
        case .negative: retainedStart = free; retainedEnd = zero; originAtUpperEnd = true
        }
        start = .authored(.zero); end = .authored(.zero); coefficientWidth = .one
        refinementDepth = max(chart.sourceDepth, attachment.approachDepth)
        normalizedDomain = try .init(lower: 0, upper: 1)
    }

    private init(copy source: Self, start: OriginalSingularFieldEndpoint, end: OriginalSingularFieldEndpoint,
        coefficientWidth: ExactRationalCoefficient, depth: Int) {
        identity = source.identity; original = source.original; sourceDomain = source.sourceDomain
        self.start = start; self.end = end; normalizedDomain = source.normalizedDomain
        retainedStart = source.retainedStart; retainedEnd = source.retainedEnd; originAtUpperEnd = source.originAtUpperEnd
        self.coefficientWidth = coefficientWidth; refinementDepth = depth
    }
    static func == (a: Self, b: Self) -> Bool { a.identity == b.identity }
    func hash(into hasher: inout Hasher) { hasher.combine(identity) }

    func refined(usage: inout OriginalQueryExecution) throws -> Self {
        guard refinementDepth < usage.effectiveLimits.maximumSubdivisionDepth else { throw rationalAlgebraFailure("Original ramified refinement exhausted causal depth.") }
        func endpoint(_ value: OriginalSingularFieldEndpoint) throws -> OriginalSingularFieldEndpoint {
            switch value { case .authored: value
            case .algebraic(let root): try .algebraic(root.refinedOnce(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)) }
        }
        let first = try endpoint(start), last = try endpoint(end)
        let depth = max(try rationalAlgebraCount(refinementDepth, 1), max(first.depth, last.depth))
        try usage.visitSilhouetteCell(depth: depth)
        return try .init(copy: self, start: first, end: last,
            coefficientWidth: coefficientWidth.divided(by: .natural(2, usage: &usage), usage: &usage), depth: depth)
    }

    func enclosure(over parameter: ScalarInterval, field: OriginalSurfaceSilhouetteField,
        usage: inout OriginalQueryExecution) throws -> SurfaceSilhouetteCurveEnclosure {
        guard parameter.lower >= 0, parameter.upper <= 1 else { throw rationalAlgebraFailure("Original ramified query exceeds its normalized source traversal.") }
        let slope: OutwardScalarInterval
        let startBounds: OutwardScalarInterval, endBounds: OutwardScalarInterval
        if let retainedStart, let retainedEnd {
            let gain = try retainedEnd.subtracting(retainedStart, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            guard case .positive = try gain.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
                throw rationalAlgebraFailure("Original half-chart traversal slope is not exactly positive.")
            }
            startBounds = try retainedStart.enclosure(maximumWidth: coefficientWidth, inheritedDepth: refinementDepth,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            endBounds = try retainedEnd.enclosure(maximumWidth: coefficientWidth, inheritedDepth: refinementDepth,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            slope = try gain.enclosure(maximumWidth: coefficientWidth, inheritedDepth: refinementDepth,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        } else {
            let lowerSlope = try end.lower.subtracting(start.upper, usage: &usage)
            let upperSlope = try end.upper.subtracting(start.lower, usage: &usage)
            guard lowerSlope.isPositive else { throw rationalAlgebraFailure("Original ramified endpoint slope is not exactly positive.") }
            let first = try start.lower.outwardInterval(usage: &usage), last = try start.upper.outwardInterval(usage: &usage)
            let a = try end.lower.outwardInterval(usage: &usage), b = try end.upper.outwardInterval(usage: &usage)
            let low = try lowerSlope.outwardInterval(usage: &usage), high = try upperSlope.outwardInterval(usage: &usage)
            slope = .init(lower: low.lower, upper: high.upper)
            startBounds = .init(lower: first.lower, upper: last.upper); endBounds = .init(lower: a.lower, upper: b.upper)
        }
        let mapped: OutwardScalarInterval
        if parameter.lower == 0, parameter.upper == 0 { mapped = startBounds }
        else if parameter.lower == 1, parameter.upper == 1 { mapped = endBounds }
        else { mapped = startBounds + slope * .init(lower: parameter.lower, upper: parameter.upper) }
        guard let free = mapped.intersection(with: .init(lower: original.parameterDomain.lower, upper: original.parameterDomain.upper)) else {
            throw rationalAlgebraFailure("Original ramified image missed its retained local graph.")
        }
        let result = try original.enclosure(over: .init(lower: free.lower, upper: free.upper),
            maximumCoefficientWidth: coefficientWidth, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth,
            inheritedDepth: refinementDepth, usage: &usage)
        guard let u = OutwardScalarInterval(lower: result.originalParameters.u.lower, upper: result.originalParameters.u.upper)
                .intersection(with: .init(lower: sourceDomain.u.lower, upper: sourceDomain.u.upper)),
              let v = OutwardScalarInterval(lower: result.originalParameters.v.lower, upper: result.originalParameters.v.upper)
                .intersection(with: .init(lower: sourceDomain.v.lower, upper: sourceDomain.v.upper)) else {
            throw rationalAlgebraFailure("Original ramified graph contradicts its complete source clipping proof.")
        }
        let parameters = try SurfaceParameterBox(u: .init(lower: u.lower, upper: u.upper), v: .init(lower: v.lower, upper: v.upper))
        let spatial = try field.evaluate(over: parameters, usage: &usage).spatial
        try RationalAlgebraStorage.retain(20, of: UInt32.self, usage: &usage)
        var uv = result.originalDerivatives
        uv[0] = try .init(x: parameters.u, y: parameters.v)
        var power = OutwardScalarInterval.exact(1)
        for index in 1..<4 {
            power = power * slope
            uv[index] = try .init(x: interval(.init(lower: uv[index].x.lower, upper: uv[index].x.upper) * power),
                y: interval(.init(lower: uv[index].y.lower, upper: uv[index].y.upper) * power))
        }
        func coordinate(_ index: Int, uAxis: Bool) -> OutwardScalarInterval {
            let value = uAxis ? uv[index].x : uv[index].y
            return .init(lower: value.lower, upper: value.upper)
        }
        let du = coordinate(1, uAxis: true), dv = coordinate(1, uAxis: false)
        let duu = coordinate(2, uAxis: true), dvv = coordinate(2, uAxis: false)
        let duuu = coordinate(3, uAxis: true), dvvv = coordinate(3, uAxis: false)
        func composed(_ s: SurfaceIntervalJet) -> [OutwardScalarInterval] {
            [s.value, s.derivativeU * du + s.derivativeV * dv,
             s.secondDerivativeUU * du * du + .exact(2) * s.secondDerivativeUV * du * dv
                + s.secondDerivativeVV * dv * dv + s.derivativeU * duu + s.derivativeV * dvv,
             s.thirdDerivativeUUU * du * du * du + .exact(3) * s.thirdDerivativeUUV * du * du * dv
                + .exact(3) * s.thirdDerivativeUVV * du * dv * dv + s.thirdDerivativeVVV * dv * dv * dv
                + .exact(3) * s.secondDerivativeUU * du * duu
                + .exact(3) * s.secondDerivativeUV * (duu * dv + du * dvv)
                + .exact(3) * s.secondDerivativeVV * dv * dvv + s.derivativeU * duuu + s.derivativeV * dvvv]
        }
        let x = composed(spatial.x), y = composed(spatial.y), z = composed(spatial.z)
        var xyz: [CoordinateEnclosure3D] = []
        for index in 0..<4 { xyz.append(try .init(x: interval(x[index]), y: interval(y[index]), z: interval(z[index]))) }
        return .init(parameters: parameters, parameterDerivatives: uv, spatialDerivatives: xyz)
    }
    private func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
        guard value.isFinite else { throw rationalAlgebraFailure("Original ramified spatial or parameter derivative is nonfinite.") }
        return try .init(lower: value.lower, upper: value.upper)
    }
}
