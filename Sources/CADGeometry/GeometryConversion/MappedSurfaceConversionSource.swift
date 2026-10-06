import CADCore

/// Composes an original immutable surface source with a complete foreign UV chart.
public struct MappedSurfaceConversionSource: GeometrySurfaceConversionSource {
    public let source: any GeometrySurfaceConversionSource
    public let mapping: any GeometrySurfaceParameterMapping

    public init(source: any GeometrySurfaceConversionSource,
        mapping: any GeometrySurfaceParameterMapping) {
        self.source = source
        self.mapping = mapping
    }

    public func validate(over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try mapping.validate(over: parameters, tolerance: tolerance)
        let map = try mapping.enclosure(over: parameters, tolerance: tolerance)
        try source.validate(over: SurfaceParameterBox(u: map.u.value, v: map.v.value), tolerance: tolerance)
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try CurrentTaskCancellationChecker().checkCancellation()
        let uv = try mapping.parameter(u: u, v: v, tolerance: tolerance)
        let result = try source.point(u: uv.u, v: uv.v, tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    public func enclosure(over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        try CurrentTaskCancellationChecker().checkCancellation()
        try mapping.validate(over: parameters, tolerance: tolerance)
        let map = try mapping.enclosure(over: parameters, tolerance: tolerance)
        let image = SurfaceParameterBox(u: map.u.value, v: map.v.value)
        try source.validate(over: image, tolerance: tolerance)
        let original = try source.enclosure(over: image, tolerance: tolerance)
        typealias Vector = GeometryConversionCertification.VectorBounds
        func outward(_ interval: ScalarInterval) -> OutwardScalarInterval {
            OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
        }
        let a = Vector(original.tangentU), b = Vector(original.tangentV)
        let aa = Vector(original.secondDerivativeUU), ab = Vector(original.secondDerivativeUV)
        let bb = Vector(original.secondDerivativeVV)
        let uu = outward(map.u.derivativeU), uv = outward(map.u.derivativeV)
        let vu = outward(map.v.derivativeU), vv = outward(map.v.derivativeV)
        func second(_ uFirst: OutwardScalarInterval, _ vFirst: OutwardScalarInterval,
            _ uSecond: OutwardScalarInterval, _ vSecond: OutwardScalarInterval,
            _ uHessian: ScalarInterval, _ vHessian: ScalarInterval) -> Vector {
            aa * (uFirst * uSecond) + ab * (uFirst * vSecond + vFirst * uSecond)
                + bb * (vFirst * vSecond) + a * outward(uHessian) + b * outward(vHessian)
        }
        func coordinates(_ vector: Vector) throws -> CoordinateEnclosure3D {
            guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Mapped surface differential arithmetic is nonfinite.")
            }
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: vector.x.lower, upper: vector.x.upper),
                y: ScalarInterval(lower: vector.y.lower, upper: vector.y.upper),
                z: ScalarInterval(lower: vector.z.lower, upper: vector.z.upper))
        }
        let result = try SurfaceDifferentialEnclosure(position: original.position,
            tangentU: coordinates(a * uu + b * vu), tangentV: coordinates(a * uv + b * vv),
            secondDerivativeUU: coordinates(second(uu, vu, uu, vu, map.u.secondDerivativeUU, map.v.secondDerivativeUU)),
            secondDerivativeUV: coordinates(second(uu, vu, uv, vv, map.u.secondDerivativeUV, map.v.secondDerivativeUV)),
            secondDerivativeVV: coordinates(second(uv, vv, uv, vv, map.u.secondDerivativeVV, map.v.secondDerivativeVV)))
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }
}
