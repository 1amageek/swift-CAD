import CADCore

extension DefaultNativeExactRelationResolver {
    func curveMap<A: ExactScalarAdmission & ~Copyable>(_ curve: BSplineCurve3D,
        selected: ScalarInterval?, field: Field, tolerance: ModelingTolerance,
        degree: Int, using admission: inout A
    ) throws -> ExactParametricMap<ExactRationalScalarDomain> {
        guard degree >= 0, curve.degree <= degree else { throw NativeExactRelationFailure.invalidDegree }
        guard !curve.isPeriodic else { throw NativeExactRelationFailure.unsupportedCoverage }
        let law = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            try curve.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
            let span = try singleSpan(curve.knots, degree: curve.degree,
                count: curve.controlPointCount, usage: &usage)
            return try OriginalRationalCurvePolynomial(source: curve, spanIndex: span,
                tolerance: tolerance, usage: &usage)
        }.value
        let native = try ScalarInterval(lower: curve.knots[curve.degree],
            upper: curve.knots[curve.controlPointCount])
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: selected == nil ? 1 : 2, of: ScalarInterval.self))
        return try map(laws: law.homogeneous, native: [native], selected: selected.map { [$0] },
            field: field, using: &admission)
    }

    func surfaceMap<A: ExactScalarAdmission & ~Copyable>(_ surface: BSplineSurface3D,
        selected: SurfaceParameterBox?, field: Field, tolerance: ModelingTolerance,
        degree: Int, using admission: inout A
    ) throws -> ExactParametricMap<ExactRationalScalarDomain> {
        guard degree >= 0, max(surface.uDegree, surface.vDegree) <= degree else {
            throw NativeExactRelationFailure.invalidDegree
        }
        guard !surface.isUPeriodic, !surface.isVPeriodic else { throw NativeExactRelationFailure.unsupportedCoverage }
        let law = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            try surface.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
            _ = try singleSpan(surface.uKnots, degree: surface.uDegree,
                count: surface.uControlPointCount, usage: &usage)
            _ = try singleSpan(surface.vKnots, degree: surface.vDegree,
                count: surface.vControlPointCount, usage: &usage)
            let box = SurfaceParameterBox(
                u: try .init(lower: surface.uKnots[surface.uDegree], upper: surface.uKnots[surface.uControlPointCount]),
                v: try .init(lower: surface.vKnots[surface.vDegree], upper: surface.vKnots[surface.vControlPointCount]))
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
            let spans = try prepared.originalIntersectionNativeSpans(over: box, tolerance: tolerance,
                maximumSpanCount: 1, consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: { try RationalAlgebraStorage.retainBytes($0, usage: &usage) })
            guard spans.count == 1, let span = spans.first else { throw NativeExactRelationFailure.unsupportedCoverage }
            return try OriginalRationalSurfacePolynomial(source: surface, native: span,
                domain: box, view: .init(x: 0, y: 0, z: 1), tolerance: tolerance, usage: &usage)
        }.value
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: selected == nil ? 2 : 4, of: ScalarInterval.self))
        return try map(laws: law.homogeneous, native: [law.domain.u, law.domain.v],
            selected: selected.map { [$0.u, $0.v] }, field: field, using: &admission)
    }

    private func singleSpan<B: RationalAlgebraAdmitting>(_ knots: [Double], degree: Int,
        count: Int, usage: inout B) throws -> Int {
        var selected: Int?
        for index in degree..<count {
            try usage.consumeExactWork(1)
            if knots[index] < knots[index + 1] {
                guard selected == nil else { throw NativeExactRelationFailure.unsupportedCoverage }
                selected = index
            }
        }
        guard let selected else { throw NativeExactRelationFailure.unsupportedCoverage }
        return selected
    }

    private func map<A: ExactScalarAdmission & ~Copyable>(laws: [ExactBivariatePolynomial],
        native: [ScalarInterval], selected: [ScalarInterval]?, field: Field, using admission: inout A
    ) throws -> ExactParametricMap<ExactRationalScalarDomain> {
        let cells = try Cells(field: field, variableCount: native.count, using: &admission)
        let roots = try ExactRealRootDomain(field: field, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: native.count,
            of: ExactRealRootInterval<Field.Value>.self))
        var polynomials: [ExactPolynomial<Field>] = []; polynomials.reserveCapacity(4)
        var domains: [ExactRealRootInterval<Field.Value>] = []; domains.reserveCapacity(native.count)
        for law in laws {
            try admission.consumeWork(1)
            let terms = try ExactScalarNumericAccess.withAdmission(&admission) {
                try law.orderedTerms(usage: &$0)
            }.value
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: terms.count,
                of: ExactPolynomialTerm<Field.Value>.self))
            var imported: [ExactPolynomialTerm<Field.Value>] = []; imported.reserveCapacity(terms.count)
            for (power, coefficient) in terms {
                try admission.consumeWork(native.count)
                guard native.count == 2 || power.v == 0 else { throw NativeExactRelationFailure.unsupportedCoverage }
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: native.count, of: Int.self))
                let powers = native.count == 1 ? [power.u] : [power.u, power.v]
                imported.append(.init(powers: powers, coefficient: try field.importingBase(coefficient, using: &admission)))
            }
            polynomials.append(try cells.polynomials.polynomial(terms: imported, using: &admission))
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
