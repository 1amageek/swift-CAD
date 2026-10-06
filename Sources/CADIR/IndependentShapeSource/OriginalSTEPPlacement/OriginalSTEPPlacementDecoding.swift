#if !hasFeature(Embedded)
import CADCore
import CADGeometry

/// Native admission for original placement records and their retained arrays.
package enum OriginalSTEPPlacementDecoding {
    static func admitRecord(from decoder: Decoder, work: Int) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else {
            throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
        }
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        let allowance = try NativeRationalSourceDecodingContext.allowance(from: decoder)
        try allowance.visitExactCell(depth: 0)
        try allowance.consumeExactWork(work)
    }

    static func adjustments(from decoder: Decoder) throws -> [OriginalSTEPPlacementAdjustment] {
        try retainedArray(OriginalSTEPPlacementAdjustment.self, from: decoder)
    }

    static func retainedArray<Value: Decodable>(_ type: Value.Type, from decoder: Decoder) throws -> [Value] {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else {
            throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
        }
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        let allowance = try NativeRationalSourceDecodingContext.allowance(from: decoder)
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
        try allowance.consumeExactWork(count)
        try allowance.retainExactStorage(words)
        var result: [Value] = []
        result.reserveCapacity(count)
        while !source.isAtEnd { result.append(try source.decode(Value.self)) }
        return result
    }
}
#endif
