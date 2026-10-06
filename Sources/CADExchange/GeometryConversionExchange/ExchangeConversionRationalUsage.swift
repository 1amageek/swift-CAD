import CADGeometry

struct ExchangeConversionRationalUsage: RationalAlgebraAdmitting {
    let admission: GeometryConversionAdmission
    mutating func visitExactCell(depth: Int) throws {
        guard let maximum = admission.maximumAlgebraicDepth, depth >= 0, depth <= maximum else {
            throw GeometryConversionError.resourceLimitExceeded("Hosted chart exhausted its explicit algebra depth.")
        }
        try admission.chargeWork()
    }
    mutating func consumeExactWork(_ count: Int) throws { try admission.chargeWork(count) }
    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Hosted chart storage overflow.") }
        try admission.chargeStorage(bytes: bytes.partialValue)
    }
}
