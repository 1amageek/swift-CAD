public enum SketchCurveChainResolutionError: Error, Equatable, Sendable {
    case unsupportedSelectedEntity
    case degenerateSegment
    case branched
    case closed
    case disconnected
}
