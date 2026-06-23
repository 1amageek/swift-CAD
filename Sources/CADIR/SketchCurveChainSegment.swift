import CADCore

public struct SketchCurveChainSegment: Sendable, Hashable {
    public var entityID: SketchEntityID
    public var startReference: SketchReference
    public var endReference: SketchReference

    public init(
        entityID: SketchEntityID,
        startReference: SketchReference,
        endReference: SketchReference
    ) {
        self.entityID = entityID
        self.startReference = startReference
        self.endReference = endReference
    }
}
