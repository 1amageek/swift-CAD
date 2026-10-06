/// Complete structural expansion and its consumption of the assembly operation work ceiling.
public struct AssemblyExpansionResult: Sendable {
    public let occurrences: [ExpandedAssemblyOccurrence]
    public let consumedWork: Int
    public init(occurrences: [ExpandedAssemblyOccurrence], consumedWork: Int) {
        self.occurrences = occurrences
        self.consumedWork = consumedWork
    }
}
