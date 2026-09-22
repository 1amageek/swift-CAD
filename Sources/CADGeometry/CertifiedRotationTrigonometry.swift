import CADCore

/// Bounded Taylor evaluation on [-1, 1], followed by four double-angle steps.
/// Inputs are enclosed real angles, not unverified libm outputs.
package enum CertifiedRotationTrigonometry {
    package static func inverseTangent(
        _ value: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> OutwardScalarInterval {
        guard value.isFinite, value.lower >= 0, value.upper <= 16 else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance, message: "Certified inverse tangent requires an interval in [0, 16].")
        }
        if value.upper == 0 { return .exact(0) }
        var x = value
        for _ in 0..<5 {
            let squared = .exact(1) + x * x
            let root = OutwardScalarInterval(lower: squared.lower.squareRoot().nextDown,
                upper: squared.upper.squareRoot().nextUp)
            guard let reduced = x.divided(by: .exact(1) + root), reduced.isFinite else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Inverse tangent range reduction is not certifiable.")
            }
            x = reduced
        }
        guard x.absoluteUpperBound <= 0.0625 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Inverse tangent series argument exceeds its certified range.")
        }
        let negativeSquare = -(x * x)
        var power = x
        var sum = x
        for index in 1..<20 {
            power = power * negativeSquare
            guard let term = power.divided(by: .exact(Double(2 * index + 1))) else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Inverse tangent series denominator is invalid.")
            }
            sum = sum + term
        }
        return (sum + OutwardScalarInterval(lower: -0x1p-164, upper: 0x1p-164)) * .exact(32)
    }

    package static func evaluate(
        _ angle: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (cosine: OutwardScalarInterval, sine: OutwardScalarInterval) {
        guard angle.isFinite, angle.lower >= -16, angle.upper <= 16 else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                tolerance: tolerance, message: "Certified rotation supports absolute source angles up to 16 radians.")
        }
        if angle.lower == 0, angle.upper == 0 { return (.exact(1), .exact(0)) }
        let x = angle * .exact(0.0625)
        let negativeSquare = -(x * x)
        var sineTerm = x
        var cosineTerm = OutwardScalarInterval.exact(1)
        var sine = sineTerm
        var cosine = cosineTerm
        for index in 1..<20 {
            // Positive integer denominators cannot contain zero.
            guard let nextSine = (sineTerm * negativeSquare).divided(by: .exact(Double((2 * index) * (2 * index + 1)))),
                  let nextCosine = (cosineTerm * negativeSquare).divided(by: .exact(Double((2 * index - 1) * (2 * index)))) else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Rotation Taylor denominator is not representable.")
            }
            sineTerm = nextSine
            cosineTerm = nextCosine
            sine = sine + sineTerm
            cosine = cosine + cosineTerm
        }
        // For |x| <= 1, the omitted Taylor terms are bounded by 1/40! < 2^-150.
        let remainder = OutwardScalarInterval(lower: -0x1p-150, upper: 0x1p-150)
        sine = sine + remainder
        cosine = cosine + remainder
        for _ in 0..<4 {
            let nextSine = .exact(2) * sine * cosine
            cosine = cosine * cosine - sine * sine
            sine = nextSine
        }
        guard sine.isFinite, cosine.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Rotation Taylor enclosure overflowed.")
        }
        return (cosine, sine)
    }
}
