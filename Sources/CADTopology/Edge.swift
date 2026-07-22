import CADCore

/// A trimmed exact 3D curve bounded by two vertices.
public struct Edge: Codable, Equatable, Sendable {
    public var id: EdgeID
    public var curveID: CurveID
    public var startVertexID: VertexID
    public var endVertexID: VertexID
    public var trim: CurveTrim?

    public init(
        id: EdgeID = EdgeID(),
        curveID: CurveID,
        startVertexID: VertexID,
        endVertexID: VertexID,
        trim: CurveTrim? = nil
    ) {
        self.id = id
        self.curveID = curveID
        self.startVertexID = startVertexID
        self.endVertexID = endVertexID
        self.trim = trim
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case curveID
        case startVertexID
        case endVertexID
        case trim
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .id,
                .curveID,
                .startVertexID,
                .endVertexID,
                .trim,
            ],
            in: decoder
        )
        id = try container.decode(EdgeID.self, forKey: .id)
        curveID = try container.decode(CurveID.self, forKey: .curveID)
        startVertexID = try container.decode(VertexID.self, forKey: .startVertexID)
        endVertexID = try container.decode(VertexID.self, forKey: .endVertexID)
        trim = try container.decodeIfPresent(CurveTrim.self, forKey: .trim)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(curveID, forKey: .curveID)
        try container.encode(startVertexID, forKey: .startVertexID)
        try container.encode(endVertexID, forKey: .endVertexID)
        try container.encodeIfPresent(trim, forKey: .trim)
    }
}
