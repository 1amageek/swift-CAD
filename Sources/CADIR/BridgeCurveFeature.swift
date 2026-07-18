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

    public func validate(tolerance: ModelingTolerance) throws {
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

    private enum CodingKeys: String, CodingKey {
        case curve
        case parameter
        case orientation
        case requiredLevel
        case derivativeMagnitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.curve, .parameter, .orientation, .requiredLevel, .derivativeMagnitude],
            in: decoder
        )
        curve = try container.decode(Curve3D.self, forKey: .curve)
        parameter = try container.decode(Double.self, forKey: .parameter)
        orientation = try container.decode(CurveFrameOrientation.self, forKey: .orientation)
        requiredLevel = try container.decode(CurveContinuityLevel.self, forKey: .requiredLevel)
        derivativeMagnitude = try container.decodeIfPresent(
            Double.self,
            forKey: .derivativeMagnitude
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encode(parameter, forKey: .parameter)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(requiredLevel, forKey: .requiredLevel)
        try container.encodeIfPresent(derivativeMagnitude, forKey: .derivativeMagnitude)
    }
}

public struct BridgeCurveFeature: Codable, Sendable, Hashable {
    public var start: BridgeCurveEndpointTarget
    public var end: BridgeCurveEndpointTarget
    public var continuityTolerances: CurveContinuityTolerances

    public init(
        start: BridgeCurveEndpointTarget,
        end: BridgeCurveEndpointTarget,
        continuityTolerances: CurveContinuityTolerances
    ) {
        self.start = start
        self.end = end
        self.continuityTolerances = continuityTolerances
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try start.validate(tolerance: tolerance)
        try end.validate(tolerance: tolerance)
        try continuityTolerances.validate()
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case continuityTolerances
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.start, .end, .continuityTolerances],
            in: decoder
        )
        start = try container.decode(BridgeCurveEndpointTarget.self, forKey: .start)
        end = try container.decode(BridgeCurveEndpointTarget.self, forKey: .end)
        continuityTolerances = try container.decode(
            CurveContinuityTolerances.self,
            forKey: .continuityTolerances
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(continuityTolerances, forKey: .continuityTolerances)
    }
}
