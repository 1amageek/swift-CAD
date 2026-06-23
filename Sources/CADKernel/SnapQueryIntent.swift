public enum SnapQueryIntent: String, Codable, Sendable, Hashable {
    case precisePoint
    case vertex
    case edge
    case curve
    case face
    case edgePoint
    case curvePoint
    case surfacePoint

    public var candidateKinds: Set<SnapCandidateKind> {
        switch self {
        case .precisePoint:
            return SnapCandidateKind.all
        case .vertex:
            return [.vertex]
        case .edge, .edgePoint:
            return [.edge]
        case .curve:
            return [.curve]
        case .curvePoint:
            return [.curvePoint]
        case .face, .surfacePoint:
            return [.face]
        }
    }

    public func priority(for kind: SnapCandidateKind) -> Int? {
        switch self {
        case .precisePoint:
            switch kind {
            case .vertex:
                return 0
            case .edge:
                return 1
            case .curvePoint:
                return 2
            case .curve:
                return 3
            case .face:
                return 4
            }
        case .vertex:
            return kind == .vertex ? 0 : nil
        case .edge, .edgePoint:
            return kind == .edge ? 0 : nil
        case .curve:
            return kind == .curve ? 0 : nil
        case .curvePoint:
            return kind == .curvePoint ? 0 : nil
        case .face, .surfacePoint:
            return kind == .face ? 0 : nil
        }
    }
}
