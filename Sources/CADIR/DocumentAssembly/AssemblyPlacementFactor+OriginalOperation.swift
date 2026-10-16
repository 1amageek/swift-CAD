import CADCore
import CADGeometry

extension AssemblyPlacementFactor {
    /// Retains the authored direct operation, including its original inverse tag.
    public func originalOperation(tolerance: ModelingTolerance,
        maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalAffineOperation {
        try tolerance.validate()
        guard maximumSourceDepth > 0 else { throw AssemblyError.invalidSource("Original placement source depth must be positive.") }
        try execution.consumeWork(1)
        let inverse: Bool
        switch self { case .forward: inverse = false; case .inverse: inverse = true }
        switch originalPlacement {
        case .rigid(let frame):
            try execution.consumeWork(12)
            try frame.validate(tolerance: tolerance)
            guard !frame.reversesOrientation else { throw AssemblyError.invalidPlacement }
            let transform = try originalPlacement.affineTransform
            return inverse ? .inverse(transform) : .forward(transform)
        case .affine(let transform):
            return inverse ? .inverse(transform) : .forward(transform)
        case .step(let source):
            let law = try source.originalNormalizedAffineSource(using: &execution, maximumSourceDepth: maximumSourceDepth)
            return inverse ? .normalizedInverse(law) : .normalizedForward(law)
        case .word:
            throw AssemblyError.invalidSource("A placement factor cannot contain a nested word.")
        }
    }
    public func originalOperationWord(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalAffineOperationWord {
        let operation = try originalOperation(tolerance: tolerance, maximumSourceDepth: maximumSourceDepth, using: &execution)
        return try OriginalAffineOperationWord(operation: operation,
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &execution)
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
