import CADCore

/// Original homogeneous laws without differential or interval-jet preparation.
package struct OriginalRationalSurfaceHomogeneous: Sendable {
    package let source: BSplineSurface3D
    package let domain: SurfaceParameterBox
    package let uSpanIndex: Int
    package let vSpanIndex: Int
    package let homogeneous: [ExactBivariatePolynomial]

    package init<B: RationalAlgebraAdmitting>(source: BSplineSurface3D,
        uSpanIndex: Int, vSpanIndex: Int, tolerance: ModelingTolerance,
        usage: inout B) throws {
        try source.validate(tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
        try usage.consumeExactWork(1)
        guard !source.isUPeriodic, !source.isVPeriodic,
            uSpanIndex >= source.uDegree, uSpanIndex < source.uControlPointCount,
            vSpanIndex >= source.vDegree, vSpanIndex < source.vControlPointCount,
            source.uKnots[uSpanIndex] < source.uKnots[uSpanIndex + 1],
            source.vKnots[vSpanIndex] < source.vKnots[vSpanIndex + 1] else {
            throw rationalAlgebraFailure("Homogeneous source requires validated positive nonperiodic native spans.")
        }
        let domain = SurfaceParameterBox(
            u: try .init(lower: source.uKnots[uSpanIndex], upper: source.uKnots[uSpanIndex + 1]),
            v: try .init(lower: source.vKnots[vSpanIndex], upper: source.vKnots[vSpanIndex + 1]))
        try self.init(validatedSource: source, domain: domain, uSpanIndex: uSpanIndex,
            vSpanIndex: vSpanIndex, uTranslation: 0, vTranslation: 0, usage: &usage)
    }

    package init<B: RationalAlgebraAdmitting>(source: BSplineSurface3D,
        native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        domain: SurfaceParameterBox, tolerance: ModelingTolerance, usage: inout B) throws {
        try native.validate(on: source, over: domain, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) })
        try self.init(validatedSource: source, domain: domain, uSpanIndex: native.uSpanIndex,
            vSpanIndex: native.vSpanIndex, uTranslation: native.originalUTranslation,
            vTranslation: native.originalVTranslation, usage: &usage)
    }

    private init<B: RationalAlgebraAdmitting>(validatedSource source: BSplineSurface3D,
        domain: SurfaceParameterBox, uSpanIndex: Int, vSpanIndex: Int,
        uTranslation: Double, vTranslation: Double, usage: inout B) throws {
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        self.source = source; self.domain = domain
        self.uSpanIndex = uSpanIndex; self.vSpanIndex = vSpanIndex
        let uBasis = try OriginalRationalBSplineBasis.powerPolynomials(knots: source.uKnots, degree: source.uDegree,
            span: uSpanIndex, alongU: true, translation: uTranslation, usage: &usage)
        let vBasis = try OriginalRationalBSplineBasis.powerPolynomials(knots: source.vKnots, degree: source.vDegree,
            span: vSpanIndex, alongU: false, translation: vTranslation, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var h = [ExactBivariatePolynomial](repeating: .zero, count: 4)
        for i in (uSpanIndex - source.uDegree)...uSpanIndex {
            for j in (vSpanIndex - source.vDegree)...vSpanIndex {
                guard let ub = uBasis[i], let vb = vBasis[j] else {
                    throw rationalAlgebraFailure("Missing original native rational basis coefficient.")
                }
                let basis = try ub.multiplied(by: vb, usage: &usage)
                let weight = try ExactRationalCoefficient.originalDouble(source.weights[j][i], usage: &usage)
                let point = source.controlPoints[j][i]
                for axis in 0..<3 {
                    let coordinate: Double
                    switch axis { case 0: coordinate = point.x; case 1: coordinate = point.y; default: coordinate = point.z }
                    let coefficient = try ExactRationalCoefficient.originalDouble(coordinate, usage: &usage)
                        .multiplied(by: weight, usage: &usage)
                    h[axis] = try h[axis].adding(basis.scaled(by: coefficient, usage: &usage), usage: &usage)
                }
                h[3] = try h[3].adding(basis.scaled(by: weight, usage: &usage), usage: &usage)
            }
        }
        homogeneous = h
        try exactScalarTaskCheckpoint()
    }
}
