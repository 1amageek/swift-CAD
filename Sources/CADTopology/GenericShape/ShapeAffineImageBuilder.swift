import CADCore
import CADGeometry

/// Adapts authored forward affine factors to the common original-word image.
struct ShapeAffineImageBuilder {
    func transform(_ source: BRepModel, by transforms: [AffineTransform3D],
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> BRepModel {
        try tolerance.validate(); try Task.checkCancellation(); try consumeWork(0)
        guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: tolerance, message: "Original affine image requires nonnegative caller depth admission.")
        }
        guard !transforms.isEmpty else { return source }
        var usage = ShapeAffineWordAdmission(maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: nil)
        let bytes = transforms.count.multipliedReportingOverflow(by: MemoryLayout<OriginalAffineOperation>.stride)
        guard !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original forward affine factor storage overflowed.")
        }
        try usage.retainBytes(bytes.partialValue)
        var factors: [OriginalAffineOperation] = []
        factors.reserveCapacity(transforms.count)
        for transform in transforms {
            try usage.visitExactCell(depth: 0)
            factors.append(.forward(transform))
        }
        let word = try OriginalAffineOperationWord(factors: factors, usage: &usage)
        return try ShapeAffineWordImageBuilder().transform(source, by: word,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: nil)
    }
}
