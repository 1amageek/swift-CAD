import CADCore
import CADGeometry

public struct BridgeCurveFeature: Sendable, Hashable {
    public var start: BridgeCurveEndpointReference
    public var end: BridgeCurveEndpointReference
    public var continuityTolerances: CurveContinuityTolerances

    public init(
        start: BridgeCurveEndpointReference,
        end: BridgeCurveEndpointReference,
        continuityTolerances: CurveContinuityTolerances
    ) {
        self.start = start
        self.end = end
        self.continuityTolerances = continuityTolerances
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.consumeWork(1); try tolerance.validate()
        try start.validate(tolerance: tolerance, using: &execution)
        try end.validate(tolerance: tolerance, using: &execution)
        try execution.consumeWork(1); try continuityTolerances.validate()
        guard start.curve != end.curve || start.end != end.end else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bridge curve endpoints must identify two distinct evaluated endpoints."
            )
        }

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case continuityTolerances
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.start, .end, .continuityTolerances],
            in: decoder
        )
        start = try container.decode(BridgeCurveEndpointReference.self, forKey: .start)
        end = try container.decode(BridgeCurveEndpointReference.self, forKey: .end)
        continuityTolerances = try container.decode(
            CurveContinuityTolerances.self,
            forKey: .continuityTolerances
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(continuityTolerances, forKey: .continuityTolerances)
    }
#endif
}

#if !hasFeature(Embedded)
extension BridgeCurveFeature: Codable {}
#endif
