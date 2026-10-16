import CADCore

/// Checked dimensions shared by conversion allocation and work admission.
enum GeometryConversionDimensions {
    static func product(_ factors: Int...) throws -> Int {
        var value = 1
        for factor in factors {
            let result = value.multipliedReportingOverflow(by: factor)
            guard factor >= 0, !result.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Conversion dimension arithmetic overflowed.")
            }
            value = result.partialValue
        }
        return value
    }
}
