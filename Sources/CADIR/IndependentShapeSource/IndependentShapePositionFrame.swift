import CADCore

/// Original position entity identity and the length parameter unit of its local generator.
public struct IndependentShapePositionFrame: Equatable, Sendable {
    public let frameID: IndependentShapeFrameID
    public let parameterLengthUnit: LengthUnit?
    public let originalIGESAdjustments: [OriginalIGESPlacementAdjustment]
    public init(frameID: IndependentShapeFrameID, parameterLengthUnit: LengthUnit? = nil, originalIGESAdjustments: [OriginalIGESPlacementAdjustment] = []) {
        self.frameID = frameID; self.parameterLengthUnit = parameterLengthUnit; self.originalIGESAdjustments = originalIGESAdjustments
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case frameID, parameterLengthUnit, originalIGESAdjustments }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 3)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.frameID, .parameterLengthUnit, .originalIGESAdjustments], in: decoder)
        frameID = try c.decode(IndependentShapeFrameID.self, forKey: .frameID)
        guard c.contains(.parameterLengthUnit) else {
            throw DecodingError.keyNotFound(CodingKeys.parameterLengthUnit,
                .init(codingPath: c.codingPath, debugDescription: "Original parameter unit is required nullable."))
        }
        parameterLengthUnit = try c.decodeIfPresent(LengthUnit.self, forKey: .parameterLengthUnit)
        originalIGESAdjustments = try OriginalSTEPPlacementDecoding.retainedArray(OriginalIGESPlacementAdjustment.self,
            from: c.superDecoder(forKey: .originalIGESAdjustments))
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(frameID, forKey: .frameID); try c.encode(parameterLengthUnit, forKey: .parameterLengthUnit)
        try c.encode(originalIGESAdjustments, forKey: .originalIGESAdjustments)
    }
    #endif
}

#if !hasFeature(Embedded)
extension IndependentShapePositionFrame: Codable {}
#endif
