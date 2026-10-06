import CADCore

/// Exact original homogeneous source law on one admitted native chart.
package struct OriginalRationalSurfacePolynomial: Sendable {
    package let source: BSplineSurface3D
    package let domain: SurfaceParameterBox
    package let uSpanIndex: Int
    package let vSpanIndex: Int
    package let homogeneous: [ExactBivariatePolynomial]
    package let normalNumerators: [ExactBivariatePolynomial]
    package let silhouetteNumerator: ExactBivariatePolynomial

    package init<B: RationalAlgebraAdmitting>(source: BSplineSurface3D,
         native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
         domain: SurfaceParameterBox, view: Vector3D, tolerance: ModelingTolerance,
         usage: inout B) throws {
        try native.validate(on: source, over: domain, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) })
        self.source = source; self.domain = domain
        uSpanIndex = native.uSpanIndex; vSpanIndex = native.vSpanIndex
        let uBasis = try OriginalRationalBSplineBasis.powerPolynomials(knots: source.uKnots, degree: source.uDegree,
            span: native.uSpanIndex, alongU: true, translation: native.originalUTranslation, usage: &usage)
        let vBasis = try OriginalRationalBSplineBasis.powerPolynomials(knots: source.vKnots, degree: source.vDegree,
            span: native.vSpanIndex, alongU: false, translation: native.originalVTranslation, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var h = [ExactBivariatePolynomial](repeating: .zero, count: 4)
        for i in (native.uSpanIndex - source.uDegree)...native.uSpanIndex {
            for j in (native.vSpanIndex - source.vDegree)...native.vSpanIndex {
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
        let wu = try h[3].differentiated(alongU: true, usage: &usage)
        let wv = try h[3].differentiated(alongU: false, usage: &usage)
        try RationalAlgebraStorage.retain(6, of: ExactBivariatePolynomial.self, usage: &usage)
        var au: [ExactBivariatePolynomial] = [], av: [ExactBivariatePolynomial] = []
        au.reserveCapacity(3); av.reserveCapacity(3)
        for axis in 0..<3 {
            au.append(try h[axis].differentiated(alongU: true, usage: &usage)
                .multiplied(by: h[3], usage: &usage)
                .subtracting(h[axis].multiplied(by: wu, usage: &usage), usage: &usage))
            av.append(try h[axis].differentiated(alongU: false, usage: &usage)
                .multiplied(by: h[3], usage: &usage)
                .subtracting(h[axis].multiplied(by: wv, usage: &usage), usage: &usage))
        }
        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
        var normal: [ExactBivariatePolynomial] = []; normal.reserveCapacity(3)
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            normal.append(try au[b].multiplied(by: av[c], usage: &usage)
                .subtracting(au[c].multiplied(by: av[b], usage: &usage), usage: &usage))
        }
        normalNumerators = normal
        var scalar = ExactBivariatePolynomial.zero
        for axis in 0..<3 {
            let coordinate: Double
            switch axis { case 0: coordinate = view.x; case 1: coordinate = view.y; default: coordinate = view.z }
            scalar = try scalar.adding(normal[axis].scaled(by:
                .originalDouble(coordinate, usage: &usage), usage: &usage), usage: &usage)
        }
        silhouetteNumerator = scalar
    }

}
