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
}
