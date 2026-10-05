import CADCore
import CADGeometry

/// Exact word work/storage consumes the existing body preparation owner.
struct BRepDrawingWordPreparationAdmission: RationalAlgebraAdmitting {
    let owner: BRepDrawingPreparationUsage
    var maximumAlgebraicDepth: Int? = nil
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Original drawing algebra depth is negative.")
        }
        if let maximumAlgebraicDepth, depth > maximumAlgebraicDepth {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original drawing algebra exceeds the caller depth capability.")
        }
        try owner.consume()
    }
    mutating func consumeExactWork(_ count: Int) throws { try owner.consume(count) }
    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original drawing word storage count overflowed.")
        }
        try owner.consume(bytes.partialValue)
    }
    mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }

}
