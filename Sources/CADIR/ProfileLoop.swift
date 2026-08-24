import CADCore

/// One exact, ordered, closed boundary loop of a planar material region.
public struct ProfileLoop: Sendable, Hashable {
    /// Tessellated samples used only by planar predicates, previews, and sampling consumers.
    public var vertices: [Point3D]
    /// Exact ordered boundary segments used to construct B-rep topology.
    public var boundarySegments: [ProfileBoundarySegment]

    public init(
        vertices: [Point3D],
        boundarySegments: [ProfileBoundarySegment]? = nil
    ) {
        self.vertices = vertices
        self.boundarySegments = boundarySegments ?? Self.lineBoundarySegments(for: vertices)
    }

    private static func lineBoundarySegments(for vertices: [Point3D]) -> [ProfileBoundarySegment] {
        guard vertices.count >= 2 else {
            return []
        }
        return vertices.indices.map { index in
            let nextIndex = (index + 1) % vertices.count
            return .line(ProfileLineSegment(
                start: vertices[index],
                end: vertices[nextIndex]
            ))
        }
    }
}
