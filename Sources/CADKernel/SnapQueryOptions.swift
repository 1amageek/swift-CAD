import CADCore

public struct SnapQueryOptions: Codable, Sendable, Hashable {
    public var maximumDistance: Double?
    public var maximumCandidateCount: Int
    public var intent: SnapQueryIntent
    public var candidateKinds: Set<SnapCandidateKind>

    public init(
        maximumDistance: Double? = nil,
        maximumCandidateCount: Int = 16,
        intent: SnapQueryIntent = .precisePoint,
        candidateKinds: Set<SnapCandidateKind> = SnapCandidateKind.all
    ) {
        self.maximumDistance = maximumDistance
        self.maximumCandidateCount = maximumCandidateCount
        self.intent = intent
        self.candidateKinds = candidateKinds
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        if let maximumDistance {
            guard maximumDistance.isFinite,
                  maximumDistance >= 0.0 else {
                throw GeometryError.invalidDistance(maximumDistance)
            }
        }
        guard maximumCandidateCount > 0 else {
            throw FeatureEvaluationError.invalidGraph("Snap query must request at least one candidate.")
        }
        guard candidateKinds.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Snap query must allow at least one candidate kind.")
        }
        guard candidateKinds.contains(where: { intent.priority(for: $0) != nil }) else {
            throw FeatureEvaluationError.invalidGraph("Snap query candidate kinds must overlap the requested intent.")
        }
    }

    public func accepts(_ kind: SnapCandidateKind) -> Bool {
        candidateKinds.contains(kind) && intent.priority(for: kind) != nil
    }

    public func priority(for kind: SnapCandidateKind) -> Int? {
        guard candidateKinds.contains(kind) else {
            return nil
        }
        return intent.priority(for: kind)
    }
}
