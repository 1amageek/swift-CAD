import CADCore

/// Admits exact normal-factor work through the original tessellation invocation.
struct OriginalPoleExactProofUsage: RationalAlgebraAdmitting {
    var proofUsage: OriginalTessellationProofUsage
    let depth: Int
    let tolerance: ModelingTolerance
    /// Exact algebra storage uses UInt32 word slots in this shared proof counter.
    static var storageByteStride: Int { MemoryLayout<UInt32>.stride }
    mutating func visitExactCell(depth childDepth:Int) throws {
        guard childDepth >= 0, childDepth <= 32 else {
            throw GeometryConversionError.resourceLimitExceeded("Original pole algebra exceeded its supported root depth.")
        }
        try proofUsage.consume(depth:depth,tolerance:tolerance)
    }
    mutating func consumeExactWork(_ count:Int) throws {
        guard count >= 0 else { throw GeometryConversionError.invalidInput("Original exact normal work must be nonnegative.") }
        for _ in 0..<count { try proofUsage.consume(depth:depth,tolerance:tolerance) }
    }
    mutating func retainExactStorage(_ count:Int) throws { try consumeExactWork(count) }
}
