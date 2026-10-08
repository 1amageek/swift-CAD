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
            let uSpan = try singleSpan(surface.uKnots, degree: surface.uDegree,
                count: surface.uControlPointCount, usage: &usage)
            let vSpan = try singleSpan(surface.vKnots, degree: surface.vDegree,
                count: surface.vControlPointCount, usage: &usage)
            return try OriginalRationalSurfaceHomogeneous(source: surface,
                uSpanIndex: uSpan, vSpanIndex: vSpan, tolerance: tolerance, usage: &usage)
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
            let terms = law.originalCoefficients
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
            // Admit sort workspace before mutation; sort only the final term buffer.
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: imported.count,
                of: ExactPolynomialTerm<Field.Value>.self))
            try imported.sort { lhs, rhs in
                try admission.consumeWork(native.count + 1)
                for index in lhs.powers.indices {
                    if lhs.powers[index] != rhs.powers[index] { return lhs.powers[index] > rhs.powers[index] }
                }
                return false
            }
            polynomials.append(try cells.polynomials.polynomial(orderedTerms: imported, using: &admission))
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
