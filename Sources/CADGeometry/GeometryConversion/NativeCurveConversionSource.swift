import CADCore

public struct NativeCurveConversionSource: GeometryCurveConversionSource {
    public let curve: Curve3D
    private let prepared: PreparedCurveDifferentialEncloser

    public init(_ curve: Curve3D, tolerance: ModelingTolerance) throws {
        self.curve = curve
        try curve.validate(tolerance: tolerance)
        prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance)
    }
    public func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard parameters.width > 0, parameters.width.isFinite,
              try curve.parameterDomain.containsSpan(from: parameters.lower, to: parameters.upper, tolerance: tolerance) else {
            throw GeometryConversionError.invalidInput("Curve conversion requires a finite, positive, contained parameter interval.")
        }
    }
    public func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        let value = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        return (value.position, value.firstDerivative)
    }
    public func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        let jet = try prepared.thirdOrderIntervalJet(over: parameters, tolerance: tolerance)
        func coordinates(_ key: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>) throws -> CoordinateEnclosure3D {
            let x = jet.x[keyPath: key], y = jet.y[keyPath: key], z = jet.z[keyPath: key]
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: x.lower, upper: x.upper),
                y: ScalarInterval(lower: y.lower, upper: y.upper), z: ScalarInterval(lower: z.lower, upper: z.upper))
        }
        return try CurveDifferentialEnclosure(position: coordinates(\.value),
            firstDerivative: coordinates(\.derivativeU), secondDerivative: coordinates(\.secondDerivativeUU))
    }
}
