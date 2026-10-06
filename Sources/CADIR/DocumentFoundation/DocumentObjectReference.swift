import CADCore

/// A symbolic persistent identity. Resolution requires an explicit document snapshot.
public struct DocumentObjectReference: Hashable, Sendable {
    public var documentID: DocumentID
    public var target: DocumentObjectTarget

    public init(documentID: DocumentID, target: DocumentObjectTarget = .document) {
        self.documentID = documentID
        self.target = target
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case documentID, target }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.documentID, .target], in: decoder)
        documentID = try c.decode(DocumentID.self, forKey: .documentID)
        target = try c.decode(DocumentObjectTarget.self, forKey: .target)
    }
    #endif
}

#if !hasFeature(Embedded)
extension DocumentObjectReference: Codable {}
#endif
