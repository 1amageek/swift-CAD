import CADCore

/// Exact original homogeneous source law on one admitted native chart.
package struct OriginalRationalSurfacePolynomial: Sendable {
    /// Native basis provenance; a spatial-word image retains this parent source.
    package let source: BSplineSurface3D
    package let domain: SurfaceParameterBox
    package let uSpanIndex: Int
    package let vSpanIndex: Int
    package let homogeneous: [ExactBivariatePolynomial]
    package let normalNumerators: [ExactBivariatePolynomial]
    package let silhouetteNumerator: ExactBivariatePolynomial

    package init<B: ExactScalarAdmission & ~Copyable>(source: BSplineSurface3D,
         native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
         domain: SurfaceParameterBox, view: Vector3D, tolerance: ModelingTolerance,
         usage: inout B) throws {
        let law = try OriginalRationalSurfaceHomogeneous(source: source, native: native,
            domain: domain, tolerance: tolerance, usage: &usage)
        try self.init(source: source, domain: domain, uSpanIndex: native.uSpanIndex,
            vSpanIndex: native.vSpanIndex, homogeneous: law.homogeneous, view: view, usage: &usage)
    }

    /// Applies an admitted exact rational spatial word without changing the original UV basis.
    package func applying<B: ExactScalarAdmission & ~Copyable>(prepared word: PreparedOriginalAffineOperationWord,
        view: Vector3D, usage: inout B) throws -> Self {
        let coefficients = try word.exactRationalCoefficients(usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var transformed: [ExactBivariatePolynomial] = []
        transformed.reserveCapacity(4)
        for row in 0..<3 {
            var value = try homogeneous[3].scaled(by: coefficients[row * 4 + 3], usage: &usage)
            for column in 0..<3 {
                try usage.consumeWork(1)
                value = try value.adding(homogeneous[column].scaled(by:
                    coefficients[row * 4 + column], usage: &usage), usage: &usage)
            }
            transformed.append(value)
        }
        transformed.append(homogeneous[3])
        return try Self(source: source, domain: domain, uSpanIndex: uSpanIndex,
            vSpanIndex: vSpanIndex, homogeneous: transformed, view: view, usage: &usage)
    }

    private init<B: ExactScalarAdmission & ~Copyable>(source: BSplineSurface3D,
        domain: SurfaceParameterBox, uSpanIndex: Int, vSpanIndex: Int,
        homogeneous h: [ExactBivariatePolynomial], view: Vector3D, usage: inout B) throws {
        self.source = source; self.domain = domain
        self.uSpanIndex = uSpanIndex; self.vSpanIndex = vSpanIndex
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
