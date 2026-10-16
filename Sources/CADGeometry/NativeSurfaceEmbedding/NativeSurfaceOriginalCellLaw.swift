import CADCore

/// Immutable original coefficient law shared by every subdivision of one owner.
struct NativeSurfaceOriginalCellLaw: Sendable {
    let native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    let source: BSplineSurface3D
    let tolerance: ModelingTolerance
    private let tangentU: [ExactBivariatePolynomial]
    private let tangentV: [ExactBivariatePolynomial]
    private let proofDepth: ExactScalarDepth

    init<A: ExactScalarAdmission & ~Copyable>(native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        source: BSplineSurface3D, tolerance: ModelingTolerance,
        using execution: inout A) throws {
        let prepared = try execution.withProofScope { execution in
        let domain = SurfaceParameterBox(u: native.uBounds, v: native.vBounds)
        let original = try OriginalRationalSurfacePolynomial(source: source, native: native,
            domain: domain, view: .unitZ, tolerance: tolerance, usage: &execution)
        let derivatives = try OriginalRationalSurfaceDerivativeLaw(original: original,
            throughOrder: 1, usage: &execution)
        guard let u = derivatives.partials.first(where: { $0.uOrder == 1 && $0.vOrder == 0 }),
              let v = derivatives.partials.first(where: { $0.uOrder == 0 && $0.vOrder == 1 }) else {
            throw GeometryConversionError.invalidInput("Original native tangent authority lost its first-order partials.")
        }
            return (u: u.numerators, v: v.numerators, depth: try execution.depth)
        }
        self.native = native; self.source = source; self.tolerance = tolerance
        tangentU = prepared.u; tangentV = prepared.v; proofDepth = prepared.depth
    }

    func fields<A: ExactScalarAdmission & ~Copyable>(over box: SurfaceParameterBox, stationary: Set<SurfaceParameterBoundary>,
        using execution: inout A) throws
        -> (RationalBezierSurfaceDifferentialBounds, BoundingBox3D) {
        try execution.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try native.validate(on: source, over: box, tolerance: tolerance,
            using: &execution)
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
                upper: side == .uUpper, usage: &execution) }
            else { v = try removingCommonFactor(v, alongU: false, at: boundary,
                upper: side == .vUpper, usage: &execution) }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: ExactBivariatePolynomial.self))
        var normal: [ExactBivariatePolynomial] = []
        normal.reserveCapacity(3)
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            normal.append(try u[b].multiplied(by: v[c], usage: &execution)
                .subtracting(u[c].multiplied(by: v[b], usage: &execution), usage: &execution))
        }
        func vector(_ polynomials: [ExactBivariatePolynomial]) throws -> IntervalVector3DBounds {
            try .init(x: polynomials[0].enclosure(over: box, usage: &execution),
                y: polynomials[1].enclosure(over: box, usage: &execution),
                z: polynomials[2].enclosure(over: box, usage: &execution))
        }
        let differential = try RationalBezierSurfaceDifferentialBounds(originalTangentU: vector(u),
            originalTangentV: vector(v), originalNormal: vector(normal))
        let jet = try native.intervalJet(overClosedBox: box, on: source, tolerance: tolerance,
            using: &execution)
        let bounds = try BoundingBox3D(minimum: .init(x: jet.x.value.lower,
                y: jet.y.value.lower, z: jet.z.value.lower),
            maximum: .init(x: jet.x.value.upper, y: jet.y.value.upper, z: jet.z.value.upper))
        return (differential, bounds)
    }

    private func removingCommonFactor<A: ExactScalarAdmission & ~Copyable>(_ original: [ExactBivariatePolynomial],
        alongU: Bool, at boundary: Double, upper: Bool,
        usage: inout A) throws -> [ExactBivariatePolynomial] {
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
        try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: ExactBivariatePolynomial.self))
        return try original.map { try $0.dividedExactly(by: power, usage: &usage).scaled(by: sign, usage: &usage) }
    }
}
