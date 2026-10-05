public enum SnapCandidateKind: String, CaseIterable, Sendable, Hashable {
    case vertex
    case edge
    case curvePoint
    case curve
    case face

    public static let all: Set<SnapCandidateKind> = Set(allCases)
}

#if !hasFeature(Embedded)
extension SnapCandidateKind: Codable {}
#endif
