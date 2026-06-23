public enum SnapCandidateRole: String, Codable, Sendable, Hashable {
    case topologyVertex
    case edgeProjection
    case curveProjection
    case curveStart
    case curveEnd
    case curveMidpoint
    case faceProjection
}
