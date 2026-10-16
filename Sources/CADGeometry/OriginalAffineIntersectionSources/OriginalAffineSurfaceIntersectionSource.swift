import CADCore

/// Exact homogeneous Native surface law under its retained original rational word.
package struct OriginalAffineSurfaceIntersectionSource: Sendable {
    package let image: OriginalAffineWordSurface3D
    package let preparedWord: PreparedOriginalAffineOperationWord
    package let nativeSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package let nativeLaw: OriginalRationalSurfacePolynomial
    package let homogeneous: [ExactBivariatePolynomial]
    package let uDomain: OriginalRationalParameterDomain
    package let vDomain: OriginalRationalParameterDomain
    package var denominator: ExactBivariatePolynomial { homogeneous[3] }

    package init<B: ExactScalarAdmission & ~Copyable>(image: OriginalAffineWordSurface3D,
        nativeSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        domain: SurfaceParameterBox, tolerance: ModelingTolerance,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard remainingSourceDepth > 0, (0...32).contains(maximumAlgebraicDepth) else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original affine Native source requires remaining source and selected algebra depth.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This original affine intersection checkpoint
        // admits one aperiodic Native rational span only. Public composition must use
        // genuine family/chart issuers before other descendants can publish source laws.
        guard case .bSpline(let surface) = image.source,
            !surface.isUPeriodic, !surface.isVPeriodic else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original affine intersection source requires an aperiodic Native rational descendant.")
        }
        try image.operationWord.validateOriginal(tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &usage)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Normalized algebraic original words need
        // their existing ordered-field homogeneous issuer. This rational checkpoint
        // is called by source composition and cannot substitute rounded coefficients.
        if let _ = try image.preparedWord.originalNormalizedFrame(usage: &usage) {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original normalized words require ordered-field homogeneous source authority.")
        }
        try surface.validate(tolerance: tolerance, using: &usage)
        let native = try OriginalRationalSurfacePolynomial(source: surface, native: nativeSpan,
            domain: domain, view: .unitZ, tolerance: tolerance, usage: &usage)
        let coefficients = try image.preparedWord.exactRationalCoefficients(usage: &usage)
        guard native.homogeneous.count == 4, !native.homogeneous[3].isZero else {
            throw rationalAlgebraFailure("Original affine Native source requires its four laws and nonzero W.")
        }
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        var transformed: [ExactBivariatePolynomial] = []; transformed.reserveCapacity(4)
        for row in 0..<3 {
            var coordinate = ExactBivariatePolynomial.zero
            for column in 0..<4 {
                try intersectionAlgebraStep(&usage)
                coordinate = try coordinate.adding(native.homogeneous[column]
                    .scaled(by: coefficients[row * 4 + column], usage: &usage), usage: &usage)
            }
            transformed.append(coordinate)
        }
        transformed.append(native.homogeneous[3])
        let u = try OriginalRationalParameterDomain(domain.u, usage: &usage)
        let v = try OriginalRationalParameterDomain(domain.v, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try usage.consumeWork(0)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.image = image; preparedWord = image.preparedWord; self.nativeSpan = nativeSpan
        nativeLaw = native; homogeneous = transformed; uDomain = u; vDomain = v
    }
}
