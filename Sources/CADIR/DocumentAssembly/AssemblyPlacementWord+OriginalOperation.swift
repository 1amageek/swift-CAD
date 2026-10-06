import CADCore
import CADGeometry

extension AssemblyPlacementWord {
    /// Converts original root-to-leaf factors into one flat mathematical action.
    public func originalOperationWord<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws -> OriginalAffineOperationWord {
        try usage.consumeExactWork(factors.count)
        let bytes = factors.count.multipliedReportingOverflow(by: MemoryLayout<OriginalAffineOperation>.stride)
        guard !bytes.overflow else { throw AssemblyError.resourceLimitExceeded("original operation storage overflow") }
        try usage.retainExactStorage(bytes.partialValue / MemoryLayout<UInt32>.stride
            + (bytes.partialValue % MemoryLayout<UInt32>.stride == 0 ? 0 : 1))
        var operations: [OriginalAffineOperation] = []; operations.reserveCapacity(factors.count)
        for factor in factors.reversed() {
            try usage.consumeExactWork(1)
            operations.append(try factor.originalOperation(tolerance: tolerance, maximumSourceDepth: maximumSourceDepth, usage: &usage))
        }
        return try OriginalAffineOperationWord(factors: operations, tolerance: tolerance,
            maximumDepth: maximumDepth, usage: &usage)
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
