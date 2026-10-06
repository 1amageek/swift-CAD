import CADCore

/// Original native homogeneous coefficients acted on by every retained spatial word.
struct SurfaceSilhouetteNativeWordLaw: Sendable {
    let normal: OriginalFieldSurfaceNormalLaw

    init(original: OriginalRationalSurfacePolynomial, images: [OriginalAffineWordSurface3D],
        poleNormal: OriginalExactBSplinePoleNormal?, view: Vector3D,
        usage: inout SurfaceSilhouetteUsage) throws {
        guard !images.isEmpty else { throw rationalAlgebraFailure("Original native word law requires an authored word.") }
        var admission = SurfaceSilhouetteAlgebraicAdmission(usage: usage)
        defer { usage = admission.usage }
        var depth = admission.usage.maximumAlgebraicDepth
        for image in images {
            if let retained = try image.preparedWord.originalNormalizedFrame(usage: &admission) {
                // Retained preparation may impose a stricter algebraic bound;
                // it never changes the separate UV/root subdivision allowance.
                depth = min(depth, retained.maximumAlgebraicDepth)
            }
        }
        let context = try OriginalSingularFieldContext(usage: &admission)
        var transport = OriginalSingularFieldTransport()
        var coefficients: [OriginalSingularFieldPlanePolynomial] = []
        try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldPlanePolynomial.self, usage: &admission)
        coefficients.reserveCapacity(4)
        for polynomial in original.homogeneous {
            coefficients.append(try OriginalFieldHomogeneousImage.lift(polynomial,
                into: context, maximumDepth: depth, usage: &admission))
        }
        for image in images.reversed() {
            coefficients = try OriginalFieldHomogeneousImage.applying(prepared: image.preparedWord,
                to: coefficients, transport: &transport, maximumDepth: depth, usage: &admission)
        }
        var normalFactor: ExactBivariatePolynomial?
        if let poleNormal {
            for axis in 0..<3 {
                try admission.consumeExactWork(1)
                if !poleNormal.coefficients[axis].isZero {
                    normalFactor = try original.normalNumerators[axis].dividedExactly(
                        by: poleNormal.coefficients[axis], usage: &admission)
                    break
                }
            }
            guard let normalFactor, !normalFactor.isZero else {
                throw rationalAlgebraFailure("Original native pole image lost its admitted oriented quotient factor.")
            }
            for axis in 0..<3 {
                guard try poleNormal.coefficients[axis].multiplied(by: normalFactor, usage: &admission)
                    .subtracting(original.normalNumerators[axis], usage: &admission).isZero else {
                    throw rationalAlgebraFailure("Original native pole factor does not divide all oriented source normal coordinates.")
                }
            }
        }
        normal = try OriginalFieldSurfaceNormalLaw(originalHomogeneous: coefficients, view: view,
            maximumAlgebraicDepth: depth, admittedNativeNormalFactor: normalFactor, usage: &admission)
    }
}
