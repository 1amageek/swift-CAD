import CADCore

/// An oriented, loop-trimmed region of an exact surface.
public struct Face: Codable, Equatable, Sendable {
    public var id: FaceID
    public var surfaceID: SurfaceID
    public var loops: [LoopID]
    public var orientation: Orientation

    public init(
        id: FaceID = FaceID(),
        surfaceID: SurfaceID,
        loops: [LoopID],
        orientation: Orientation = .forward
    ) {
        self.id = id
        self.surfaceID = surfaceID
        self.loops = loops
        self.orientation = orientation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case surfaceID
        case loops
        case orientation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.id, .surfaceID, .loops, .orientation],
            in: decoder
        )
        id = try container.decode(FaceID.self, forKey: .id)
        surfaceID = try container.decode(SurfaceID.self, forKey: .surfaceID)
        loops = try container.decode([LoopID].self, forKey: .loops)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(surfaceID, forKey: .surfaceID)
        try container.encode(loops, forKey: .loops)
        try container.encode(orientation, forKey: .orientation)
    }
}
