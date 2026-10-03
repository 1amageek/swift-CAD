import Foundation
import CADCore

public struct DocumentAttribute: Codable, Hashable, Sendable {
    public var id: DocumentAttributeID
    public var name: String
    public var owner: DocumentObjectReference
    public var value: DocumentAttributeValue

    public init(id: DocumentAttributeID = DocumentAttributeID(), name: String,
                owner: DocumentObjectReference, value: DocumentAttributeValue) {
        self.id = id; self.name = name; self.owner = owner; self.value = value
    }

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
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentFoundationError.invalidName(name)
        }
        try value.validate()
    }
}
