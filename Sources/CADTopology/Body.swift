import CADCore

/// A topological body composed of one or more owned shells.
public struct Body: Codable, Equatable, Sendable {
    public var id: BodyID
    public var shellIDs: [ShellID]
    public var kind: BodyKind
    public var name: String?
    public var material: MaterialID?

    public init(
        id: BodyID = BodyID(),
        shellIDs: [ShellID],
        kind: BodyKind = .solid,
        name: String? = nil,
        material: MaterialID? = nil
    ) {
        self.id = id
        self.shellIDs = shellIDs
        self.kind = kind
        self.name = name
        self.material = material
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case shellIDs
        case kind
        case name
        case material
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BodyID.self, forKey: .id)
        shellIDs = try container.decode([ShellID].self, forKey: .shellIDs)
        kind = try container.decodeIfPresent(BodyKind.self, forKey: .kind) ?? .solid
        name = try container.decodeIfPresent(String.self, forKey: .name)
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(shellIDs, forKey: .shellIDs)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(material, forKey: .material)
    }
}
