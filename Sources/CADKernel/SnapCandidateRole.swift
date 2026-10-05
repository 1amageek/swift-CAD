public enum SnapCandidateRole: String, Sendable, Hashable {
    case topologyVertex
    case edgeProjection
    case curveProjection
    case curveStart
    case curveEnd
    case curveMidpoint
    case faceProjection
}

#if !hasFeature(Embedded)
extension SnapCandidateRole: Codable {}
#endif
