import CADCore

/// An oriented connected collection of faces owned by one body.
public struct Shell: Codable, Equatable, Sendable {
    public var id: ShellID
    public var faceIDs: [FaceID]
    public var orientation: Orientation

    public init(id: ShellID = ShellID(), faceIDs: [FaceID], orientation: Orientation = .forward) {
        self.id = id
        self.faceIDs = faceIDs
        self.orientation = orientation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case faceIDs
        case orientation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.id, .faceIDs, .orientation],
            in: decoder
        )
        id = try container.decode(ShellID.self, forKey: .id)
        faceIDs = try container.decode([FaceID].self, forKey: .faceIDs)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(faceIDs, forKey: .faceIDs)
        try container.encode(orientation, forKey: .orientation)
    }
}
