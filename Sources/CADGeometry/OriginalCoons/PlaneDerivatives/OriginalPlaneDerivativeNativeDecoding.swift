#if !hasFeature(Embedded)
import CADCore

package struct OriginalPlaneDerivativeNativeDecoding {
    @available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *)
    package static func constraints(from decoder: Decoder, usage: inout NativeRationalSourceAllowance)
        throws -> [OriginalPlaneDerivativeConstraint] {
        var input = try decoder.unkeyedContainer()
        var result: [OriginalPlaneDerivativeConstraint] = []
        while !input.isAtEnd {
            try usage.consumeExactWork(1)
            if result.count == result.capacity {
                let doubled = result.capacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Original plane constraint array capacity overflows.")
                }
                let capacity = result.capacity == 0 ? 1 : doubled.partialValue
                guard capacity > result.capacity else {
                    throw GeometryConversionError.resourceLimitExceeded("Original plane constraint array capacity overflows.")
                }
                try RationalAlgebraStorage.retain(capacity, of: OriginalPlaneDerivativeConstraint.self, usage: &usage)
                try usage.consumeExactWork(result.count)
                result.reserveCapacity(capacity)
            }
            result.append(try input.decode(OriginalPlaneDerivativeConstraint.self))
        }
        return result
    }
}
#endif
