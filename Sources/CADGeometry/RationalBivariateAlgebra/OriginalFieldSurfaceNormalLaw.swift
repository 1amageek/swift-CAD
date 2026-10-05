import CADCore

/// Original homogeneous surface normal numerators over one exact coefficient field.
package struct OriginalFieldSurfaceNormalLaw: Sendable {
    package let originalHomogeneous: [OriginalSingularFieldPlanePolynomial]
    package let normalNumerators: [OriginalSingularFieldPlanePolynomial]
    package let silhouette: OriginalFieldZeroSetAuthority
    package let view: Vector3D
    package let maximumAlgebraicDepth: Int

    package init<B: RationalAlgebraAdmitting>(originalHomogeneous: [OriginalSingularFieldPlanePolynomial],
        view: Vector3D, maximumAlgebraicDepth: Int,
        admittedNativeNormalFactor: ExactBivariatePolynomial? = nil, usage: inout B) throws {
        guard originalHomogeneous.count == 4, let first = originalHomogeneous.first,
            !originalHomogeneous[3].isZero, view.x.isFinite, view.y.isFinite, view.z.isFinite,
            view.x != 0 || view.y != 0 || view.z != 0 else {
            throw rationalAlgebraFailure("Original field normal requires complete homogeneous source coefficients and a finite nonzero view.")
        }
        for polynomial in originalHomogeneous {
            try usage.consumeExactWork(1)
            guard polynomial.context === first.context else {
                throw rationalAlgebraFailure("Original field surface coordinates have unrelated coefficient owners.")
            }
        }
        let weight = originalHomogeneous[3]
        let wu = try weight.differentiated(alongU: true, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        let wv = try weight.differentiated(alongU: false, maximumDepth: maximumAlgebraicDepth, usage: &usage)
        try RationalAlgebraStorage.retain(6, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
        var u: [OriginalSingularFieldPlanePolynomial] = [], v: [OriginalSingularFieldPlanePolynomial] = []
        u.reserveCapacity(3); v.reserveCapacity(3)
        for axis in 0..<3 {
            let source = originalHomogeneous[axis]
            u.append(try source.differentiated(alongU: true, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .multiplied(by: weight, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .subtracting(source.multiplied(by: wu, maximumDepth: maximumAlgebraicDepth, usage: &usage),
                    maximumDepth: maximumAlgebraicDepth, usage: &usage))
            v.append(try source.differentiated(alongU: false, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .multiplied(by: weight, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .subtracting(source.multiplied(by: wv, maximumDepth: maximumAlgebraicDepth, usage: &usage),
                    maximumDepth: maximumAlgebraicDepth, usage: &usage))
        }
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
        var normal: [OriginalSingularFieldPlanePolynomial] = []; normal.reserveCapacity(3)
        var scalar = try OriginalSingularFieldPlanePolynomial(context: first.context,
            coefficients: [:], maximumDepth: maximumAlgebraicDepth, usage: &usage)
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            let cross = try u[b].multiplied(by: v[c], maximumDepth: maximumAlgebraicDepth, usage: &usage)
                .subtracting(u[c].multiplied(by: v[b], maximumDepth: maximumAlgebraicDepth, usage: &usage),
                    maximumDepth: maximumAlgebraicDepth, usage: &usage)
            let oriented: OriginalSingularFieldPlanePolynomial
            if let admittedNativeNormalFactor {
                let factor = try OriginalFieldHomogeneousImage.lift(admittedNativeNormalFactor,
                    into: first.context, maximumDepth: maximumAlgebraicDepth, usage: &usage)
                oriented = try cross.dividedExactly(by: factor, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            } else { oriented = cross }
            normal.append(oriented)
            let raw = axis == 0 ? view.x : axis == 1 ? view.y : view.z
            let coefficient = try OriginalSingularFieldElement.constant(.originalDouble(raw, usage: &usage),
                in: first.context, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            scalar = try scalar.adding(oriented.multiplied(by: .constant(coefficient,
                maximumDepth: maximumAlgebraicDepth, usage: &usage), maximumDepth: maximumAlgebraicDepth, usage: &usage),
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
        }
        self.originalHomogeneous = originalHomogeneous; normalNumerators = normal
        silhouette = try OriginalFieldZeroSetAuthority(original: scalar,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
        self.view = view; self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    /// The numerator identity is a surface zero law only on a nonzero original W.
    package func weightIsNonzero<B: RationalAlgebraAdmitting>(over domain: SurfaceParameterBox,
        inheritedDepth: Int, usage: inout B) throws -> Bool {
        try originalHomogeneous[3].partial(over: domain, uOrder: 0, vOrder: 0,
            inheritedDepth: inheritedDepth, maximumDepth: maximumAlgebraicDepth, usage: &usage).excludesZero
    }
}
