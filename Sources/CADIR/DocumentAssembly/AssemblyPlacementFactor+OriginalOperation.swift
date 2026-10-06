import CADCore
import CADGeometry

extension AssemblyPlacementFactor {
    /// Retains the authored direct operation, including its original inverse tag.
    public func originalOperation<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumSourceDepth: Int, usage: inout B) throws -> OriginalAffineOperation {
        try tolerance.validate()
        guard maximumSourceDepth > 0 else { throw AssemblyError.invalidSource("Original placement source depth must be positive.") }
        try usage.consumeExactWork(1)
        let inverse: Bool
        switch self { case .forward: inverse = false; case .inverse: inverse = true }
        switch originalPlacement {
        case .rigid(let frame):
            try usage.consumeExactWork(12)
            try frame.validate(tolerance: tolerance)
            guard !frame.reversesOrientation else { throw AssemblyError.invalidPlacement }
            let transform = try originalPlacement.affineTransform
            return inverse ? .inverse(transform) : .forward(transform)
        case .affine(let transform):
            return inverse ? .inverse(transform) : .forward(transform)
        case .step(let source):
            let law = try source.originalNormalizedAffineSource(usage: &usage, maximumSourceDepth: maximumSourceDepth)
            return inverse ? .normalizedInverse(law) : .normalizedForward(law)
        case .word:
            throw AssemblyError.invalidSource("A placement factor cannot contain a nested word.")
        }
    }
    public func originalOperationWord<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws -> OriginalAffineOperationWord {
        let operation = try originalOperation(tolerance: tolerance, maximumSourceDepth: maximumSourceDepth, usage: &usage)
        return try OriginalAffineOperationWord(operation: operation,
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
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
