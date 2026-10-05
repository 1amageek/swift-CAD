#if !hasFeature(Embedded)
import Foundation
#endif
import CADCore

public struct DocumentAttribute: Hashable, Sendable {
    public var id: DocumentAttributeID
    public var name: String
    public var owner: DocumentObjectReference
    public var value: DocumentAttributeValue

    public init(id: DocumentAttributeID = DocumentAttributeID(), name: String,
                owner: DocumentObjectReference, value: DocumentAttributeValue) {
        self.id = id; self.name = name; self.owner = owner; self.value = value
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, owner, value }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .owner, .value], in: decoder)
        id = try c.decode(DocumentAttributeID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        owner = try c.decode(DocumentObjectReference.self, forKey: .owner)
        value = try c.decode(DocumentAttributeValue.self, forKey: .value)
        try validate()
    }
    #endif

    public func validate() throws {
        guard name.contains(where: { !$0.isWhitespace }) else {
            throw DocumentFoundationError.invalidName(name)
        }
        try value.validate()
    }
}

#if !hasFeature(Embedded)
extension DocumentAttribute: Codable {}
#endif
