/// Original rational normal numerators, without a replacement surface or sampled fallback.
enum OriginalPolynomialCurveSurfaceNormal {
    static func prepare<B: RationalAlgebraAdmitting>(homogeneous h: [ExactBivariatePolynomial],
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        guard h.count == 4 else { throw rationalAlgebraFailure("An original normal requires the complete homogeneous law.") }
        let wu = try h[3].differentiated(alongU: true, usage: &usage)
        let wv = try h[3].differentiated(alongU: false, usage: &usage)
        try RationalAlgebraStorage.retain(6, of: ExactBivariatePolynomial.self, usage: &usage)
        var au: [ExactBivariatePolynomial] = [], av: [ExactBivariatePolynomial] = []
        au.reserveCapacity(3); av.reserveCapacity(3)
        for axis in 0..<3 {
            try intersectionAlgebraStep(&usage)
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
        return normal
    }
}
