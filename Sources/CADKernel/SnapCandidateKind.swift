public enum SnapCandidateKind: String, CaseIterable, Codable, Sendable, Hashable {
    case vertex
    case edge
    case curvePoint
    case curve
    case face

    public static let all: Set<SnapCandidateKind> = Set(allCases)
}
