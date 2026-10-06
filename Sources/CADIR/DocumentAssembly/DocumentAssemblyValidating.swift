import CADCore

public protocol DocumentAssemblyValidating: Sendable {
    func expand(_ assembly: DocumentAssembly, in graph: DesignGraph,
                tolerance: ModelingTolerance, limits: AssemblyResourceLimits) throws -> AssemblyExpansionResult
    func expandedOccurrences(of assembly: DocumentAssembly, in graph: DesignGraph,
                             tolerance: ModelingTolerance, limits: AssemblyResourceLimits) throws -> [ExpandedAssemblyOccurrence]
}
