import CADIR

/// Snapshot-owned local base and complete typed occurrence correspondence index.
public struct AssemblyEvaluationArtifact: Sendable, Equatable {
    public let limits: AssemblyResourceLimits
    public let local: AssemblyLocalEvaluationBase
    public let occurrences: [AssemblyOccurrenceCorrespondence]
    public init(local: AssemblyLocalEvaluationBase, occurrences: [AssemblyOccurrenceCorrespondence], limits: AssemblyResourceLimits = .standard) {
        self.limits = limits
        self.local = local; self.occurrences = occurrences
    }
}

#if !hasFeature(Embedded)
extension AssemblyEvaluationArtifact: Codable {}
#endif
