public enum GeneratedSubshapeRole: String, Sendable, Hashable {
    case body
    case vertex
    case edge
    case face
    case startFace
    case endFace
    case sideFace
}

#if !hasFeature(Embedded)
extension GeneratedSubshapeRole: Codable {}
#endif
