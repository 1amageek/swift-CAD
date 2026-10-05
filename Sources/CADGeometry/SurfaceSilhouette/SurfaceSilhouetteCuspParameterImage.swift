import CADCore

/// Finite original cusp traversal, including its stationary singular parameter.
struct SurfaceSilhouetteCuspParameterImage: Hashable, Sendable {
    let cusp: OriginalRationalBinomialCusp
    let nativeCover: ScalarInterval
    let uDerivatives: [ExactBivariatePolynomial]
    let vDerivatives: [ExactBivariatePolynomial]

    init(cusp: OriginalRationalBinomialCusp, start: ExactMonotoneGraphEndpoint,
        end: ExactMonotoneGraphEndpoint, usage: inout SurfaceSilhouetteUsage) throws {
        self.cusp = cusp
        let low = try start.lower.outwardInterval(usage: &usage)
        let high = try end.upper.outwardInterval(usage: &usage)
        nativeCover = try ScalarInterval(lower: low.lower, upper: high.upper)
        try usage.retain(8)
        var u = [cusp.u], v = [cusp.v]
        for _ in 0..<3 {
            u.append(try u[u.count - 1].differentiated(alongU: true, usage: &usage))
            v.append(try v[v.count - 1].differentiated(alongU: true, usage: &usage))
        }
        uDerivatives = u; vDerivatives = v
    }
    static func == (a: Self, b: Self) -> Bool { a.cusp.original == b.cusp.original }
    func hash(into hasher: inout Hasher) {
        hasher.combine(cusp.oddCoordinateAlongU); hasher.combine(cusp.characteristicExponent); hasher.combine(cusp.branchMultiplicity); hasher.combine(cusp.parameterExponent)
        hasher.combine(cusp.gain.canonicalSign); hasher.combine(cusp.gain.canonicalNumeratorWords)
        hasher.combine(cusp.gain.canonicalDenominatorWords)
        for center in [cusp.centerU, cusp.centerV] {
            hasher.combine(center.canonicalSign); hasher.combine(center.canonicalNumeratorWords)
            hasher.combine(center.canonicalDenominatorWords)
        }
    }

    func enclosure(over range: ScalarInterval, image: SurfaceSilhouetteFreeParameterImage,
        field: OriginalSurfaceSilhouetteField, chart: SurfaceParameterBox,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteCurveEnclosure {
        let mapped = try image.mapped(over: range, nativeCover: nativeCover, usage: &usage)
        let zero = try ScalarInterval(lower: 0, upper: 0)
        let parameterBox = SurfaceParameterBox(u: mapped.parameter, v: zero)
        try usage.retain(8)
        var u: [OutwardScalarInterval] = [], v: [OutwardScalarInterval] = []
        var scale = OutwardScalarInterval.exact(1)
        for order in 0..<4 {
            if order > 0 { scale = scale * mapped.derivative }
            u.append(try uDerivatives[order].enclosure(over: parameterBox, usage: &usage) * scale)
            v.append(try vDerivatives[order].enclosure(over: parameterBox, usage: &usage) * scale)
        }
        guard let originalU = u[0].intersection(with: .init(lower: chart.u.lower, upper: chart.u.upper)),
              let originalV = v[0].intersection(with: .init(lower: chart.v.lower, upper: chart.v.upper)) else {
            throw rationalAlgebraFailure("Original cusp traversal contradicts its certified native rectangle.")
        }
        u[0] = originalU; v[0] = originalV
        func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw rationalAlgebraFailure("Original cusp derivative has no finite enclosure.") }
            return try .init(lower: value.lower, upper: value.upper)
        }
        let parameters = try SurfaceParameterBox(u: interval(u[0]), v: interval(v[0]))
        let source = try field.evaluate(over: parameters, usage: &usage).spatial
        func composed(_ s: SurfaceIntervalJet) -> [OutwardScalarInterval] {
            let first = s.derivativeU * u[1] + s.derivativeV * v[1]
            let second = s.secondDerivativeUU * u[1] * u[1]
                + .exact(2) * s.secondDerivativeUV * u[1] * v[1]
                + s.secondDerivativeVV * v[1] * v[1] + s.derivativeU * u[2] + s.derivativeV * v[2]
            let third = s.thirdDerivativeUUU * u[1] * u[1] * u[1]
                + .exact(3) * s.thirdDerivativeUUV * u[1] * u[1] * v[1]
                + .exact(3) * s.thirdDerivativeUVV * u[1] * v[1] * v[1]
                + s.thirdDerivativeVVV * v[1] * v[1] * v[1]
                + .exact(3) * s.secondDerivativeUU * u[1] * u[2]
                + .exact(3) * s.secondDerivativeUV * (u[2] * v[1] + u[1] * v[2])
                + .exact(3) * s.secondDerivativeVV * v[1] * v[2]
                + s.derivativeU * u[3] + s.derivativeV * v[3]
            return [s.value, first, second, third]
        }
        try usage.retain(20)
        let x = composed(source.x), y = composed(source.y), z = composed(source.z)
        var uv: [CoordinateEnclosure2D] = [], xyz: [CoordinateEnclosure3D] = []
        for index in 0..<4 {
            uv.append(try .init(x: interval(u[index]), y: interval(v[index])))
            xyz.append(try .init(x: interval(x[index]), y: interval(y[index]), z: interval(z[index])))
        }
        return .init(parameters: parameters, parameterDerivatives: uv, spatialDerivatives: xyz)
    }
}
