import CADCore

extension DefaultNativeExactRelationResolver {
    func curveMap<A: ExactScalarAdmission & ~Copyable>(_ curve: BSplineCurve3D,
        selected: ScalarInterval?, field: Field, tolerance: ModelingTolerance,
        degree: Int, using admission: inout A
    ) throws -> NativeExactPreparedMap {
        guard degree >= 0, curve.degree <= degree else { throw NativeExactRelationFailure.invalidDegree }
        guard !curve.isPeriodic else { throw NativeExactRelationFailure.unsupportedCoverage }
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 0)
        let source = try DefaultOriginalSourceBindingIssuer(
            provider: OriginalBSplineCurveSnapshotProvider(tolerance: tolerance))
            .bind(curve, limits: limits, using: &admission)
        let original = source.original
        let span = try singleSpan(original.knots, degree: original.degree,
            count: original.controlPointCount, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Int.self))
        let chart = try source.chart(OriginalBSplineChartSelection(spans: [span]),
            limits: limits, using: &admission)
        let law = try DefaultOriginalBSplineChartIssuer<BSplineCurve3D, Field>()
            .issue(source: source, chart: chart, field: field, limits: limits, using: &admission)
        let native = try ScalarInterval(lower: original.knots[original.degree],
            upper: original.knots[original.controlPointCount])
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: selected == nil ? 1 : 2, of: ScalarInterval.self))
        let prepared = try map(laws: law.homogeneous, native: [native], selected: selected.map { [$0] },
            field: field, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: NativeExactPreparedMap.self))
        try admission.checkpoint()
        return NativeExactPreparedMap(map: prepared, sourceLaw: .curve(law))
    }

    func surfaceMap<A: ExactScalarAdmission & ~Copyable>(_ surface: BSplineSurface3D,
        selected: SurfaceParameterBox?, field: Field, tolerance: ModelingTolerance,
        degree: Int, using admission: inout A
    ) throws -> NativeExactPreparedMap {
        guard degree >= 0, max(surface.uDegree, surface.vDegree) <= degree else {
            throw NativeExactRelationFailure.invalidDegree
        }
        guard !surface.isUPeriodic, !surface.isVPeriodic else { throw NativeExactRelationFailure.unsupportedCoverage }
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 0)
        let source = try DefaultOriginalSourceBindingIssuer(
            provider: OriginalBSplineSurfaceSnapshotProvider(tolerance: tolerance))
            .bind(surface, limits: limits, using: &admission)
        let original = source.original
        let uSpan = try singleSpan(original.uKnots, degree: original.uDegree,
            count: original.uControlPointCount, using: &admission)
        let vSpan = try singleSpan(original.vKnots, degree: original.vDegree,
            count: original.vControlPointCount, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Int.self))
        let chart = try source.chart(OriginalBSplineChartSelection(spans: [uSpan, vSpan]),
            limits: limits, using: &admission)
        let law = try DefaultOriginalBSplineChartIssuer<BSplineSurface3D, Field>()
            .issue(source: source, chart: chart, field: field, limits: limits, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: selected == nil ? 2 : 4, of: ScalarInterval.self))
        let native = [try ScalarInterval(lower: original.uKnots[original.uDegree],
                upper: original.uKnots[original.uControlPointCount]),
            try ScalarInterval(lower: original.vKnots[original.vDegree],
                upper: original.vKnots[original.vControlPointCount])]
        let prepared = try map(laws: law.homogeneous, native: native,
            selected: selected.map { [$0.u, $0.v] }, field: field, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: NativeExactPreparedMap.self))
        try admission.checkpoint()
        return NativeExactPreparedMap(map: prepared, sourceLaw: .surface(law))
    }

    private func singleSpan<A: ExactScalarAdmission & ~Copyable>(_ knots: [Double], degree: Int,
        count: Int, using admission: inout A) throws -> Int {
        var selected: Int?
        for index in degree..<count {
            try admission.consumeWork(1)
            if knots[index] < knots[index + 1] {
                guard selected == nil else { throw NativeExactRelationFailure.unsupportedCoverage }
                selected = index
            }
        }
        guard let selected else { throw NativeExactRelationFailure.unsupportedCoverage }
        return selected
    }

    private func map<A: ExactScalarAdmission & ~Copyable>(laws: borrowing [ExactPolynomial<Field>],
        native: [ScalarInterval], selected: [ScalarInterval]?, field: Field, using admission: inout A
    ) throws -> ExactParametricMap<ExactRationalScalarDomain> {
        let cells = try Cells(field: field, variableCount: native.count, using: &admission)
        let roots = try ExactRealRootDomain(field: field, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: native.count,
            of: ExactRealRootInterval<Field.Value>.self))
        var polynomials: [ExactPolynomial<Field>] = []; polynomials.reserveCapacity(4)
        var domains: [ExactRealRootInterval<Field.Value>] = []; domains.reserveCapacity(native.count)
        for index in laws.indices {
            try admission.consumeWork(1)
            polynomials.append(try cells.polynomials.importing(laws[index], using: &admission))
        }
        for index in native.indices {
            try admission.consumeWork(1)
            let query = selected?[index] ?? native[index]
            guard query.lower.isFinite, query.upper.isFinite, query.lower <= query.upper else {
                throw NativeExactRelationFailure.invalidDomain
            }
            // Finite binary64 ordering is exactly the ordering of the original dyadic values.
            let lower = max(query.lower, native[index].lower), upper = min(query.upper, native[index].upper)
            if lower > upper { domains.append(try roots.emptyDomain(using: &admission)) }
            else {
                domains.append(try roots.domain(lower: .finite(field.binary64(exactly: lower, using: &admission)),
                    upper: .finite(field.binary64(exactly: upper, using: &admission)), using: &admission))
            }
        }
        let source = try cells.bind(polynomials: polynomials, domains: domains, using: &admission)
        return try Domain(cells: Cells.self, topology: .init(cells: Cells.self)).map(from: source, using: &admission)
    }
}
