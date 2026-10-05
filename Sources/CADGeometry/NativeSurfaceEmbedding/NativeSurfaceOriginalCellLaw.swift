import CADCore

/// Immutable original coefficient law shared by every subdivision of one owner.
struct NativeSurfaceOriginalCellLaw: Sendable {
    let native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    let source: BSplineSurface3D
    let tolerance: ModelingTolerance
    private let tangentU: [ExactBivariatePolynomial]
    private let tangentV: [ExactBivariatePolynomial]

    init(native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        source: BSplineSurface3D, tolerance: ModelingTolerance,
        admission: NativeSurfaceEmbeddingAdmission) throws {
        var usage = NativeSurfaceOriginalProofAllowance(admission: admission)
        let domain = SurfaceParameterBox(u: native.uBounds, v: native.vBounds)
        let original = try OriginalRationalSurfacePolynomial(source: source, native: native,
            domain: domain, view: .unitZ, tolerance: tolerance, usage: &usage)
        let derivatives = try OriginalRationalSurfaceDerivativeLaw(original: original,
            throughOrder: 1, usage: &usage)
        guard let u = derivatives.partials.first(where: { $0.uOrder == 1 && $0.vOrder == 0 }),
              let v = derivatives.partials.first(where: { $0.uOrder == 0 && $0.vOrder == 1 }) else {
            throw GeometryConversionError.invalidInput("Original native tangent authority lost its first-order partials.")
        }
        self.native = native; self.source = source; self.tolerance = tolerance
        tangentU = u.numerators; tangentV = v.numerators
    }

    func fields(over box: SurfaceParameterBox, stationary: Set<SurfaceParameterBoundary>,
        admission: NativeSurfaceEmbeddingAdmission) throws
        -> (RationalBezierSurfaceDifferentialBounds, BoundingBox3D) {
        var usage = NativeSurfaceOriginalProofAllowance(admission: admission)
        try native.validate(on: source, over: box, tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) })
        var u = tangentU, v = tangentV
        for side in [SurfaceParameterBoundary.uLower, .uUpper, .vLower, .vUpper]
            where stationary.contains(side) {
            let alongU = side == .uLower || side == .uUpper
            let boundary: Double
            switch side {
            case .uLower: boundary = box.u.lower
            case .uUpper: boundary = box.u.upper
            case .vLower: boundary = box.v.lower
            case .vUpper: boundary = box.v.upper
            }
            if alongU { u = try removingCommonFactor(u, alongU: true, at: boundary,
                upper: side == .uUpper, usage: &usage) }
            else { v = try removingCommonFactor(v, alongU: false, at: boundary,
                upper: side == .vUpper, usage: &usage) }
        }
        try usage.retainExactStorage(3)
        var normal: [ExactBivariatePolynomial] = []
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            normal.append(try u[b].multiplied(by: v[c], usage: &usage)
                .subtracting(u[c].multiplied(by: v[b], usage: &usage), usage: &usage))
        }
        func vector(_ polynomials: [ExactBivariatePolynomial]) throws -> IntervalVector3DBounds {
            try .init(x: polynomials[0].enclosure(over: box, usage: &usage),
                y: polynomials[1].enclosure(over: box, usage: &usage),
                z: polynomials[2].enclosure(over: box, usage: &usage))
        }
        let differential = try RationalBezierSurfaceDifferentialBounds(originalTangentU: vector(u),
            originalTangentV: vector(v), originalNormal: vector(normal))
        let jet = try native.intervalJet(overClosedBox: box, on: source, tolerance: tolerance,
            consumeWork: { try admission.work(1) }, consumeStorage: { try admission.storageBytes($0) })
        let bounds = try BoundingBox3D(minimum: .init(x: jet.x.value.lower,
                y: jet.y.value.lower, z: jet.z.value.lower),
            maximum: .init(x: jet.x.value.upper, y: jet.y.value.upper, z: jet.z.value.upper))
        return (differential, bounds)
    }

    private func removingCommonFactor(_ original: [ExactBivariatePolynomial],
        alongU: Bool, at boundary: Double, upper: Bool,
        usage: inout NativeSurfaceOriginalProofAllowance) throws -> [ExactBivariatePolynomial] {
        let station = try ExactRationalCoefficient.originalDouble(boundary, usage: &usage)
        var multiplicity: Int?
        for value in original where !value.isZero {
            let result = try value.dividedByBoundaryFactor(alongU: alongU, boundary: station, usage: &usage)
            multiplicity = min(multiplicity ?? result.multiplicity, result.multiplicity)
        }
        guard let multiplicity, multiplicity > 0 else { return original }
        let factor = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
            .subtracting(.constant(station, usage: &usage), usage: &usage)
        var power = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        for _ in 0..<multiplicity { power = try power.multiplied(by: factor, usage: &usage) }
        let sign = try ExactRationalCoefficient.originalDouble(upper && multiplicity & 1 == 1 ? -1 : 1, usage: &usage)
        try usage.retainExactStorage(3)
        return try original.map { try $0.dividedExactly(by: power, usage: &usage).scaled(by: sign, usage: &usage) }
    }
}
