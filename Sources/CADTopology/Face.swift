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
}
