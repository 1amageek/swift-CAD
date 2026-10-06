import CADGeometry

/// Exact directed incidence awaiting global nonzero sector winding.
struct OriginalPlanarContourIncidence: Sendable {
    struct Edge: Sendable {
        let sourceIndex: Int
        let sourceSegmentIndex: Int
        let span: OriginalCurveRootSpan3D
        let startVertex: Int
        let endVertex: Int
        let multiplicity: Int
    }

    struct End: Sendable {
        let edgeIndex: Int
        let atStart: Bool
    }

    struct Vertex: Sendable {
        let identity: Int
        let ends: [End]
        let order: OriginalPlanarCurveGermOrder
    }

    let source: PreparedOriginalPlanarContourContacts
    let edges: [Edge]
    let vertices: [Vertex]
}
