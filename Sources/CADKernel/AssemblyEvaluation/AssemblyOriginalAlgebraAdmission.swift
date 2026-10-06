import CADGeometry
import CADIR

/// Shares the assembly invocation owner, including exact limb storage and root cells.
struct AssemblyOriginalAlgebraAdmission: RationalAlgebraAdmitting {
    let usage: AssemblyEvaluationUsage
    let maximumDepth: Int
    mutating func consumeExactWork(_ count: Int) throws { try usage.consume(count) }
    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw AssemblyError.resourceLimitExceeded("original assembly algebra storage")
        }
        try usage.consume(bytes.partialValue)
    }
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= maximumDepth else {
            throw AssemblyError.resourceLimitExceeded("original assembly algebra depth")
        }
        try usage.consume()
    }
    mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }

}
