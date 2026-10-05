import CADCore

/// Checked admission immediately preceding concrete coefficient storage growth.
struct OriginalCoefficientAllocation {
    static func reserve<Element>(count: Int, of: Element.Type,
        consumeStorage: ((Int) throws -> Void)?) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original coefficient byte count overflowed.")
        }
        if let consumeStorage { try consumeStorage(bytes.partialValue) }
    }
}
