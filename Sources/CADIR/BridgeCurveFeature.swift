import CADCore

public struct BridgeCurveEndpointTarget: Codable, Sendable, Hashable {
    public var curve: Curve3D
    public var parameter: Double
    public var orientation: CurveFrameOrientation
    public var requiredLevel: CurveContinuityLevel
    public var derivativeMagnitude: Double?

    public init(
        curve: Curve3D,
        parameter: Double,
        orientation: CurveFrameOrientation = .forward,
        requiredLevel: CurveContinuityLevel,
        derivativeMagnitude: Double? = nil
    ) {
        self.curve = curve
        self.parameter = parameter
        self.orientation = orientation
        self.requiredLevel = requiredLevel
        self.derivativeMagnitude = derivativeMagnitude
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try curve.validate(tolerance: tolerance)
        guard try curve.parameterDomain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(parameter)
        }
        if let derivativeMagnitude {
            guard derivativeMagnitude.isFinite,
                  derivativeMagnitude > tolerance.distance else {
                throw GeometryError.invalidDistance(derivativeMagnitude)
            }
        }
    }

    public func continuityTarget() -> CurveContinuityTarget {
        CurveContinuityTarget(
            curve: curve,
            parameter: parameter,
            orientation: orientation
        )
    }
}

public struct BridgeCurveFeature: Codable, Sendable, Hashable {
    public var start: BridgeCurveEndpointTarget
    public var end: BridgeCurveEndpointTarget
    public var sampleCount: Int
    public var continuityTolerances: CurveContinuityTolerances

    public init(
        start: BridgeCurveEndpointTarget,
        end: BridgeCurveEndpointTarget,
        sampleCount: Int = 33,
        continuityTolerances: CurveContinuityTolerances = .standard()
    ) {
        self.start = start
        self.end = end
        self.sampleCount = sampleCount
        self.continuityTolerances = continuityTolerances
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try start.validate(tolerance: tolerance)
        try end.validate(tolerance: tolerance)
        try continuityTolerances.validate()
        guard sampleCount >= 2 else {
            throw GeometryError.invalidDistance(Double(sampleCount))
        }
    }
}
