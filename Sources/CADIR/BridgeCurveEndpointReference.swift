import CADCore

public struct BridgeCurveEndpointReference: Codable, Sendable, Hashable {
    public var curve: CurveOutputReference
    public var end: CurveEndpointEnd
    public var orientation: CurveFrameOrientation
    public var requiredLevel: CurveContinuityLevel
    public var derivativeMagnitude: Double?

    public init(
        curve: CurveOutputReference,
        end: CurveEndpointEnd,
        orientation: CurveFrameOrientation = .forward,
        requiredLevel: CurveContinuityLevel,
        derivativeMagnitude: Double? = nil
    ) {
        self.curve = curve
        self.end = end
        self.orientation = orientation
        self.requiredLevel = requiredLevel
        self.derivativeMagnitude = derivativeMagnitude
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try curve.validate()
        if let derivativeMagnitude {
            guard requiredLevel >= .tangent else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: derivativeMagnitude,
                    tolerance: tolerance,
                    message: "A bridge derivative magnitude is only meaningful for G1 or G2 continuity."
                )
            }
            guard derivativeMagnitude.isFinite,
                  derivativeMagnitude > tolerance.distance else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: derivativeMagnitude,
                    tolerance: tolerance,
                    message: "A bridge derivative magnitude must exceed the modeling distance tolerance."
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case curve
        case end
        case orientation
        case requiredLevel
        case derivativeMagnitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.curve, .end, .orientation, .requiredLevel, .derivativeMagnitude],
            in: decoder
        )
        curve = try container.decode(CurveOutputReference.self, forKey: .curve)
        end = try container.decode(CurveEndpointEnd.self, forKey: .end)
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
        try container.encode(end, forKey: .end)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(requiredLevel, forKey: .requiredLevel)
        try container.encodeIfPresent(derivativeMagnitude, forKey: .derivativeMagnitude)
    }
}
