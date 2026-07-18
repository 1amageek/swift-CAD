import CADCore

/// A trimmed exact 3D curve bounded by two vertices.
public struct Edge: Codable, Equatable, Sendable {
    public var id: EdgeID
    public var curveID: CurveID
    public var startVertexID: VertexID
    public var endVertexID: VertexID
    public var trim: CurveTrim?
    public var surfaceApproximationTolerance: Double?

    public init(
        id: EdgeID = EdgeID(),
        curveID: CurveID,
        startVertexID: VertexID,
        endVertexID: VertexID,
        trim: CurveTrim? = nil,
        surfaceApproximationTolerance: Double? = nil
    ) {
        self.id = id
        self.curveID = curveID
        self.startVertexID = startVertexID
        self.endVertexID = endVertexID
        self.trim = trim
        self.surfaceApproximationTolerance = surfaceApproximationTolerance
    }
}
