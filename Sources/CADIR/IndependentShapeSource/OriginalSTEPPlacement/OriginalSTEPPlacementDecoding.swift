#if !hasFeature(Embedded)
import CADCore
import CADGeometry

/// Native admission for original placement records and their retained arrays.
package enum OriginalSTEPPlacementDecoding {
    static func admitRecord(from decoder: Decoder, work: Int) throws {
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        var allowance = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try allowance.visitCell(axis: .value, depth: 0)
        try allowance.consumeWork(work)
    }

    static func adjustments(from decoder: Decoder) throws -> [OriginalSTEPPlacementAdjustment] {
        try retainedArray(OriginalSTEPPlacementAdjustment.self, from: decoder)
    }

    static func retainedArray<Value: Decodable>(_ type: Value.Type, from decoder: Decoder) throws -> [Value] {
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        var allowance = try NativeRationalSourceDecodingContext.execution(from: decoder)
        var source = try decoder.unkeyedContainer()
        guard let count = source.count else {
            throw NativeRationalSourceDecodingError.unboundedWordContainer
        }
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Value>.stride)
        guard count >= 0, !bytes.overflow else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Original record array storage overflow.")
        }
        let stride = MemoryLayout<UInt32>.stride
        let words = bytes.partialValue / stride + (bytes.partialValue % stride == 0 ? 0 : 1)
        try allowance.consumeWork(count)
        try RationalAlgebraStorage.retain(words, of: UInt32.self, usage: &allowance)
        var result: [Value] = []
        result.reserveCapacity(count)
        while !source.isAtEnd { result.append(try source.decode(Value.self)) }
        return result
    }
}
#endif
