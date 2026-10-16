import CADCore
import CADGeometry

extension AssemblyPlacementWord {
    /// Converts original root-to-leaf factors into one flat mathematical action.
    public func originalOperationWord(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalAffineOperationWord {
        try execution.consumeWork(factors.count)
        let bytes = factors.count.multipliedReportingOverflow(by: MemoryLayout<OriginalAffineOperation>.stride)
        guard !bytes.overflow else { throw AssemblyError.resourceLimitExceeded("original operation storage overflow") }
        try RationalAlgebraStorage.retain(bytes.partialValue / MemoryLayout<UInt32>.stride
            + (bytes.partialValue % MemoryLayout<UInt32>.stride == 0 ? 0 : 1), of: UInt32.self, usage: &execution)
        var operations: [OriginalAffineOperation] = []; operations.reserveCapacity(factors.count)
        for factor in factors.reversed() {
            try execution.consumeWork(1)
            operations.append(try factor.originalOperation(tolerance: tolerance, maximumSourceDepth: maximumSourceDepth, using: &execution))
        }
        return try OriginalAffineOperationWord(factors: operations, tolerance: tolerance,
            maximumDepth: maximumDepth, usage: &execution)
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
