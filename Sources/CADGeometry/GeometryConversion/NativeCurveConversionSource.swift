import CADCore

public struct NativeCurveConversionSource: GeometryCurveConversionSource {
    public let curve: Curve3D
    private let prepared: PreparedCurveDifferentialEncloser?

    public init(_ curve: Curve3D, tolerance: ModelingTolerance) throws {
        self.curve = curve
        try curve.validate(tolerance: tolerance)
        prepared = Self.containsPeriodicCurve(curve) ? nil
            : try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance)
    }
    private static func containsPeriodicCurve(_ curve: Curve3D) -> Bool {
        switch curve {
        case .bSpline(let value): value.isPeriodic
        case .rigidImage(let image): containsPeriodicCurve(image.source)
        case .affineImage(let image): containsPeriodicCurve(image.source)
        default: false
        }
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
    static func stablePeriodicInterval(_ parameters: ScalarInterval, domain: ParameterDomain, tolerance: ModelingTolerance) throws -> ScalarInterval {
        let scale = max(1, abs(parameters.lower), abs(parameters.upper), parameters.width)
        let resolution = max(domain.parameterResolution(tolerance: tolerance),
            tolerance.relative * scale, Double.ulpOfOne * scale * 256)
        guard resolution.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Periodic enclosure resolution is not finite.") }
        guard parameters.width <= resolution * 4 else { return parameters }
        let lower = parameters.lower - resolution * 4, upper = parameters.upper + resolution * 4
        guard lower.isFinite, upper.isFinite, lower <= parameters.lower, upper >= parameters.upper,
              upper - lower > resolution else {
            throw GeometryConversionError.resourceLimitExceeded("Periodic enclosure could not construct a stable containing interval.")
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }
    public func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        // Periodic extraction must expand the requested cycle before restricting it.
        let jet: SurfaceIntervalVectorJet
        if let prepared {
            jet = try prepared.thirdOrderIntervalJet(over: parameters, tolerance: tolerance)
        } else {
            jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
                of: curve, over: Self.stablePeriodicInterval(parameters, domain: curve.parameterDomain, tolerance: tolerance), tolerance: tolerance)
        }
        func coordinates(_ key: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>) throws -> CoordinateEnclosure3D {
            let x = jet.x[keyPath: key], y = jet.y[keyPath: key], z = jet.z[keyPath: key]
            return try CoordinateEnclosure3D(x: ScalarInterval(lower: x.lower, upper: x.upper),
                y: ScalarInterval(lower: y.lower, upper: y.upper), z: ScalarInterval(lower: z.lower, upper: z.upper))
        }
        return try CurveDifferentialEnclosure(position: coordinates(\.value),
            firstDerivative: coordinates(\.derivativeU), secondDerivative: coordinates(\.secondDerivativeUU))
    }
}
