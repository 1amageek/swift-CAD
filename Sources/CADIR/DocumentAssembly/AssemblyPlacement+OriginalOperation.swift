import CADCore
import CADGeometry

extension AssemblyPlacement {
    /// Prepares one complete original action under the caller's explicit admission.
    public func originalOperationWord<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws -> OriginalAffineOperationWord {
        switch self {
        case .word(let word):
            return try word.originalOperationWord(tolerance: tolerance, maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, usage: &usage)
        case .rigid, .affine, .step:
            return try AssemblyPlacementFactor.forward(self).originalOperationWord(tolerance: tolerance,
                maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, usage: &usage)
        }
    }
    public func applying<B: RationalAlgebraAdmitting>(to point: Point3D, tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws -> Point3D {
        let word = try originalOperationWord(tolerance: tolerance, maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, usage: &usage)
        return try word.prepared(usage: &usage).applying(to: point, usage: &usage)
    }
    public func applying<B: RationalAlgebraAdmitting>(to vector: Vector3D, tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws -> Vector3D {
        let word = try originalOperationWord(tolerance: tolerance, maximumDepth: maximumDepth, maximumSourceDepth: maximumSourceDepth, usage: &usage)
        return try word.prepared(usage: &usage).applying(to: vector, usage: &usage)
    }
}
