public enum SnapCandidateKind: String, CaseIterable, Codable, Sendable, Hashable {
    case vertex
    case edge
    case face

    public static let all: Set<SnapCandidateKind> = Set(allCases)
}
