import CADCore
import CADIR

public protocol SketchConstraintSolving: Sendable {
    func solve(
        _ sketch: Sketch,
        parameters: ResolvedParameterTable,
        tolerance: ModelingTolerance
    ) throws -> SketchConstraintSolveResult
}
