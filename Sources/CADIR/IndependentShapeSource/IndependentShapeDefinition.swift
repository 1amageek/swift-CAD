import CADCore

/// A real representation-map identity referencing its single original frame owner.
public struct IndependentShapeDefinition: Equatable, Sendable {
    public let id: IndependentShapeDefinitionID
    public let representationID: IndependentShapeRepresentationID
    public let originFrameID: IndependentShapeFrameID?
    public let originalIGES: IndependentShapeIGESDefinitionSource?
    public init(id: IndependentShapeDefinitionID = .init(), representationID: IndependentShapeRepresentationID,
                originFrameID: IndependentShapeFrameID?, originalIGES: IndependentShapeIGESDefinitionSource? = nil) {
        self.id = id; self.representationID = representationID; self.originFrameID = originFrameID; self.originalIGES = originalIGES
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, representationID, originFrameID, originalIGES }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 4)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .representationID, .originFrameID, .originalIGES], in: decoder)
        id = try c.decode(IndependentShapeDefinitionID.self, forKey: .id)
        representationID = try c.decode(IndependentShapeRepresentationID.self, forKey: .representationID)
        guard c.contains(.originFrameID) else {
            throw DecodingError.keyNotFound(CodingKeys.originFrameID, .init(codingPath: decoder.codingPath, debugDescription: "Explicit nullable mapping origin is required."))
        }
        originFrameID = try c.decodeIfPresent(IndependentShapeFrameID.self, forKey: .originFrameID)
        originalIGES = try c.decode(IndependentShapeIGESDefinitionSource?.self, forKey: .originalIGES)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(representationID, forKey: .representationID)
        if let originFrameID { try c.encode(originFrameID, forKey: .originFrameID) }
        else { try c.encodeNil(forKey: .originFrameID) }
        try c.encode(originalIGES, forKey: .originalIGES)
    }
    #endif
}

#if !hasFeature(Embedded)
extension IndependentShapeDefinition: Codable {}
#endif
