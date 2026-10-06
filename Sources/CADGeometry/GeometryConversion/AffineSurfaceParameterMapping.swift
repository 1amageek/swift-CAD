import CADCore

/// Constant-Jacobian chart composition, including angular-unit gains and reversals.
public struct AffineSurfaceParameterMapping: GeometrySurfaceParameterMapping {
    public let transform: SurfaceParameterAffineTransform

    public init(transform: SurfaceParameterAffineTransform) {
        self.transform = transform
    }

    public func validate(over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance) throws {
        try transform.validate(tolerance: tolerance)
        guard parameters.u.width.isFinite, parameters.v.width.isFinite,
              parameters.u.width > 0, parameters.v.width > 0 else {
            throw GeometryConversionError.invalidInput("An affine conversion chart requires a finite positive consumer rectangle.")
        }
    }

    public func parameter(u: Double, v: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameter {
        try CurrentTaskCancellationChecker().checkCancellation()
        try transform.validate(tolerance: tolerance)
        guard u.isFinite, v.isFinite else {
            throw GeometryConversionError.invalidInput("A chart point must have finite coordinates.")
        }
        let result = transform.applying(to: SurfaceParameter(u: u, v: v))
        guard result.u.isFinite, result.v.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Affine chart point arithmetic is nonfinite.")
        }
        return result
    }

    public func enclosure(over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance) throws -> SurfaceParameterMapEnclosure {
        try CurrentTaskCancellationChecker().checkCancellation()
        try validate(over: parameters, tolerance: tolerance)
        let u = OutwardScalarInterval(lower: parameters.u.lower, upper: parameters.u.upper)
        let v = OutwardScalarInterval(lower: parameters.v.lower, upper: parameters.v.upper)
        func coordinate(_ first: Double, _ second: Double, _ offset: Double) throws -> SurfaceParameterMapCoordinateEnclosure {
            let value: OutwardScalarInterval
            if second == 0, offset == 0, first == 1 { value = u }
            else if second == 0, offset == 0, first == -1 { value = -u }
            else if first == 0, offset == 0, second == 1 { value = v }
            else if first == 0, offset == 0, second == -1 { value = -v }
            else { value = u * .exact(first) + v * .exact(second) + .exact(offset) }
            guard value.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Affine chart interval arithmetic is nonfinite.")
            }
            let zero = try ScalarInterval(lower: 0, upper: 0)
            return try SurfaceParameterMapCoordinateEnclosure(
                value: ScalarInterval(lower: value.lower, upper: value.upper),
                derivativeU: ScalarInterval(lower: first, upper: first),
                derivativeV: ScalarInterval(lower: second, upper: second),
                secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero)
        }
        return try SurfaceParameterMapEnclosure(
            u: coordinate(transform.uu, transform.uv, transform.uOffset),
            v: coordinate(transform.vu, transform.vv, transform.vOffset))
    }
}
