import CADCore

public struct SurfaceSurfaceIntersectionDerivedRepresentation: Codable, Hashable, Sendable {
    public let curve: Curve3D
    public let firstSurfaceParameterCurve: SurfaceParameterCurve
    public let secondSurfaceParameterCurve: SurfaceParameterCurve
    public let maximumResidualUpperBound: Double
    public let certificationTolerance: ModelingTolerance

    public init(
        curve: Curve3D,
        firstSurfaceParameterCurve: SurfaceParameterCurve,
        secondSurfaceParameterCurve: SurfaceParameterCurve,
        maximumResidualUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound >= 0.0,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A derived surface-intersection representation exceeded its certified residual bound."
            )
        }
        self.curve = curve
        self.firstSurfaceParameterCurve = firstSurfaceParameterCurve
        self.secondSurfaceParameterCurve = secondSurfaceParameterCurve
        self.maximumResidualUpperBound = maximumResidualUpperBound
        certificationTolerance = tolerance
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A derived intersection representation cannot satisfy a stricter tolerance than its stored certification tolerance."
            )
        }
        try curve.validate(tolerance: tolerance)
        guard maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound >= 0.0,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A derived surface-intersection representation exceeded its certified residual bound."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case curve
        case firstSurfaceParameterCurve
        case secondSurfaceParameterCurve
        case maximumResidualUpperBound
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .curve,
                .firstSurfaceParameterCurve,
                .secondSurfaceParameterCurve,
                .maximumResidualUpperBound,
                .certificationTolerance,
            ],
            in: decoder
        )
        try self.init(
            curve: container.decode(Curve3D.self, forKey: .curve),
            firstSurfaceParameterCurve: container.decode(
                SurfaceParameterCurve.self,
                forKey: .firstSurfaceParameterCurve
            ),
            secondSurfaceParameterCurve: container.decode(
                SurfaceParameterCurve.self,
                forKey: .secondSurfaceParameterCurve
            ),
            maximumResidualUpperBound: container.decode(
                Double.self,
                forKey: .maximumResidualUpperBound
            ),
            tolerance: container.decode(
                ModelingTolerance.self,
                forKey: .certificationTolerance
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encode(firstSurfaceParameterCurve, forKey: .firstSurfaceParameterCurve)
        try container.encode(secondSurfaceParameterCurve, forKey: .secondSurfaceParameterCurve)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
