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
}
