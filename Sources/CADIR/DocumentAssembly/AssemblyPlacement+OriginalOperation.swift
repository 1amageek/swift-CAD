import CADCore
import CADGeometry

extension AssemblyPlacement {
    /// Prepares one complete original action under the caller's explicit admission.
    public func originalOperationWord(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalAffineOperationWord {
        switch self {
        case .word(let word):
            return try word.originalOperationWord(tolerance: tolerance, maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, using: &execution)
        case .rigid, .affine, .step:
            return try AssemblyPlacementFactor.forward(self).originalOperationWord(tolerance: tolerance,
                maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, using: &execution)
        }
    }
    public func applying(to point: Point3D, tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> Point3D {
        let word = try originalOperationWord(tolerance: tolerance, maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, using: &execution)
        return try word.prepared(usage: &execution).applying(to: point, usage: &execution)
    }
    public func applying(to vector: Vector3D, tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> Vector3D {
        let word = try originalOperationWord(tolerance: tolerance, maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, using: &execution)
        return try word.prepared(usage: &execution).applying(to: vector, usage: &execution)
    }
}
