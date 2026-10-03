import CADCore
import CADIR

public protocol AssemblyEvaluating: Sendable {
    func evaluate(_ assembly: DocumentAssembly, in graph: DesignGraph,
                  local: AssemblyLocalEvaluationBase, tolerance: ModelingTolerance,
                  limits: AssemblyResourceLimits) throws -> AssemblyEvaluationResult
}
