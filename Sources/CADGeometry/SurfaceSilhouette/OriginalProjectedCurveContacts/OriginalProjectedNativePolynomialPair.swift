import CADCore

/// Original screen equality polynomials retaining both homogeneous source owners.
struct OriginalProjectedNativePolynomialPair: Sendable {
    let edge: OriginalRationalCurvePolynomial
    let edgeRange: ScalarInterval
    let silhouette: OriginalSurfaceSilhouetteTrimmedCurve
    let frame: OrthographicProjectionFrame
    let surface: OriginalRationalSurfacePolynomial
    let zeroLaw: ExactBivariatePolynomial
    let horizontal: ExactSurfaceCoefficientPolynomial
    let vertical: ExactSurfaceCoefficientPolynomial
    let eliminated: ExactBivariatePolynomial?

    init(edge original: Curve3D, spanIndex: Int, over range: ScalarInterval,
        silhouette: OriginalSurfaceSilhouetteTrimmedCurve,
        frame: OrthographicProjectionFrame, usage: inout SurfaceSilhouetteUsage) throws {
        try usage.consumeSourceVisit(depth: 1)
        let originalEdge = try OriginalRationalCurvePolynomial(source: original, spanIndex: spanIndex,
            tolerance: silhouette.original.certificationTolerance,
            remainingSourceDepth: usage.maximumSourceDepth, usage: &usage)
        let first = try ExactRationalCoefficient.originalDouble(range.lower, usage: &usage)
        let last = try ExactRationalCoefficient.originalDouble(range.upper, usage: &usage)
        guard range.width > 0,
            try !first.subtracting(originalEdge.lowerParameter, usage: &usage).isNegative,
            try !originalEdge.upperParameter.subtracting(last, usage: &usage).isNegative else {
            throw rationalAlgebraFailure("Projected original edge range exceeds its selected positive native span.")
        }
        let view = silhouette.original.view
        let normal = frame.normal
        for axis in 0..<3 {
            let firstAxis = (axis + 1) % 3, secondAxis = (axis + 2) % 3
            func component(_ vector: Vector3D, _ selected: Int) -> Double {
                selected == 0 ? vector.x : selected == 1 ? vector.y : vector.z
            }
            let determinant = try ExactRationalCoefficient.originalDouble(component(view, firstAxis), usage: &usage)
                .multiplied(by: .originalDouble(component(normal, secondAxis), usage: &usage), usage: &usage)
                .subtracting(ExactRationalCoefficient.originalDouble(component(view, secondAxis), usage: &usage)
                    .multiplied(by: .originalDouble(component(normal, firstAxis), usage: &usage), usage: &usage), usage: &usage)
            guard determinant.isZero else {
                throw rationalAlgebraFailure("Projected silhouette view differs from the original screen normal direction.")
            }
        }
        let native = try silhouette.original.projectedNativePolynomialAuthority()
        self.edge = originalEdge; edgeRange = range; self.silhouette = silhouette; self.frame = frame
        surface = native.polynomial; zeroLaw = native.zeroLaw
        horizontal = try Self.equality(edge: originalEdge, surface: native.polynomial,
            direction: frame.horizontal, usage: &usage)
        vertical = try Self.equality(edge: originalEdge, surface: native.polynomial,
            direction: frame.vertical, usage: &usage)
        // A constant screen source is a direct UV system, not a degenerate resultant.
        if horizontal.degree <= 0, vertical.degree <= 0 { eliminated = nil }
        else {
            eliminated = try ExactSurfaceCoefficientResultant().eliminatingParameter(horizontal, vertical, usage: &usage)
        }
    }

    private static func equality(edge: OriginalRationalCurvePolynomial,
        surface: OriginalRationalSurfacePolynomial, direction: Vector3D,
        usage: inout SurfaceSilhouetteUsage) throws -> ExactSurfaceCoefficientPolynomial {
        guard edge.homogeneous.count == 4, surface.homogeneous.count == 4, direction.isFinite else {
            throw rationalAlgebraFailure("Original projected equality lacks complete source homogeneous coordinates.")
        }
        var curve = ExactBivariatePolynomial.zero, tensor = ExactBivariatePolynomial.zero
        for axis in 0..<3 {
            let raw = axis == 0 ? direction.x : axis == 1 ? direction.y : direction.z
            let gain = try ExactRationalCoefficient.originalDouble(raw, usage: &usage)
            curve = try curve.adding(edge.homogeneous[axis].scaled(by: gain, usage: &usage), usage: &usage)
            tensor = try tensor.adding(surface.homogeneous[axis].scaled(by: gain, usage: &usage), usage: &usage)
        }
        let weight = edge.homogeneous[3]
        guard curve.vDegree <= 0, weight.vDegree <= 0 else {
            throw rationalAlgebraFailure("Original edge screen law contains a foreign native coordinate.")
        }
        let degree = max(curve.uDegree, weight.uDegree)
        let count = try rationalAlgebraCount(max(0, degree), 1)
        try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
        var values: [ExactBivariatePolynomial] = []; values.reserveCapacity(count)
        for index in 0..<count {
            try usage.consumeWork()
            let power = try ExactBivariatePolynomial.Power(u: index, v: 0)
            let numerator = curve.originalCoefficients[power] ?? .zero
            let denominator = weight.originalCoefficients[power] ?? .zero
            values.append(try surface.homogeneous[3].scaled(by: numerator, usage: &usage)
                .subtracting(tensor.scaled(by: denominator, usage: &usage), usage: &usage))
        }
        return try .init(coefficients: values, usage: &usage)
    }
}
