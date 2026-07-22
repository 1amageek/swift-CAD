import CADCore

/// An ordered, oriented chain of coedges forming a face-local boundary.
public struct Loop: Codable, Equatable, Sendable {
    public var id: LoopID
    public var role: LoopRole
    public var coedges: [Coedge]

    /// The ordered coedge boundary consumed by topology algorithms.
    public var edges: [Coedge] {
        get { coedges }
        set { coedges = newValue }
    }

    public init(id: LoopID = LoopID(), role: LoopRole = .outer, edges: [Coedge]) {
        self.id = id
        self.role = role
        self.coedges = edges
    }

    public init(id: LoopID = LoopID(), role: LoopRole = .outer, coedges: [Coedge]) {
        self.id = id
        self.role = role
        self.coedges = coedges
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case coedges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .role, .coedges], in: decoder)
        id = try container.decode(LoopID.self, forKey: .id)
        role = try container.decode(LoopRole.self, forKey: .role)
        coedges = try container.decode([Coedge].self, forKey: .coedges)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(coedges, forKey: .coedges)
    }
}
