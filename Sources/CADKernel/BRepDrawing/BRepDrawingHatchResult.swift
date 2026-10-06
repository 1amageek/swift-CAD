import CADCore

/// One original hatch invocation and its admitted preparation contribution.
public struct BRepDrawingHatchResult: Sendable {
    public let segments: [BRepDrawingHatchSegment]
    public let consumedPreparationWork: Int
    public let retainedPreparationBytes: Int
}
