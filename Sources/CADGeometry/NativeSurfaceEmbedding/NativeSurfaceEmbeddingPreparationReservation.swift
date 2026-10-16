import CADCore

/// Checked source-shape arithmetic for concrete native coefficient storage.
struct NativeSurfaceEmbeddingPreparationReservation {
    static func product(_ factors: [Int]) throws -> Int {
        var result = 1
        for factor in factors {
            guard factor >= 0 else { throw GeometryConversionError.invalidInput("Native preparation shape cannot be negative.") }
            let next = result.multipliedReportingOverflow(by: factor)
            guard !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native preparation shape overflows.") }
            result = next.partialValue
        }
        return result
    }
    static func sum(_ values: [Int]) throws -> Int {
        var result = 0
        for value in values {
            guard value >= 0 else { throw GeometryConversionError.invalidInput("Native preparation count cannot be negative.") }
            let next = result.addingReportingOverflow(value)
            guard !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native preparation count overflows.") }
            result = next.partialValue
        }
        return result
    }
}
