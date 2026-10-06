import CADCore
import CADGeometry

/// Exact-source work and canonical word storage in the existing feature admission.
package struct OriginalDraftedConstructionAdmission: RationalAlgebraAdmitting {
    package let admission: GeometryConversionAdmission
    package init(_ admission:GeometryConversionAdmission) { self.admission = admission }
    package mutating func consumeExactWork(_ count:Int) throws { try admission.chargeWork(count) }
    package mutating func retainExactStorage(_ count:Int) throws {
        let bytes = count.multipliedReportingOverflow(by:MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original draft exact storage conversion overflows.")
        }
        try admission.chargeStorage(bytes:bytes.partialValue)
    }
    package mutating func visitExactCell(depth:Int) throws {
        guard depth >= 0, depth <= min(32,admission.maximumAlgebraicDepth ?? 32) else {
            throw GeometryConversionError.resourceLimitExceeded("Original draft exact algebra depth is exhausted.")
        }
        try admission.chargeWork()
    }
}
