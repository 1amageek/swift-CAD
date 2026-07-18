import CADCore
import CADIR

extension SketchConstraintSolveResult {
    func validatedSketch(tolerance: ModelingTolerance) throws -> Sketch {
        switch status {
        case .fullyConstrained, .underConstrained, .overConstrained:
            return sketch
        case .conflicting:
            throw KernelError(
                phase: .evaluation,
                code: .conflictingConstraints,
                residual: maximumNormalizedResidual,
                tolerance: tolerance,
                message: "Sketch constraints could not be satisfied simultaneously."
            )
        case .singular:
            throw KernelError(
                phase: .evaluation,
                code: .singularSystem,
                residual: maximumNormalizedResidual,
                tolerance: tolerance,
                message: "Sketch constraint Jacobian is singular."
            )
        }
    }
}
