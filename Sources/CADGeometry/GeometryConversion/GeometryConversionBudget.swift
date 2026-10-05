struct GeometryConversionBudget {
    var scalars: Int
    var work: Int
    var boxes: Int
    var visited = 0

    init(_ requirements: GeometryConversionRequirements) {
        scalars = requirements.maximumScalarCount
        work = requirements.maximumWorkUnits
        boxes = requirements.maximumCertificationBoxes
    }
    mutating func charge(scalars count: Int = 0, work units: Int = 0) throws {
        guard count >= 0, units >= 0, count <= scalars, units <= work else {
            throw GeometryConversionError.resourceLimitExceeded(
                "Conversion resource admission rejected \(count) scalar slots with \(scalars) remaining and \(units) work units with \(work) remaining after \(visited) certification boxes.")
        }
        scalars -= count; work -= units
    }
    mutating func visit() throws {
        try Task.checkCancellation()
        guard boxes > 0 else { throw GeometryConversionError.resourceLimitExceeded("Conversion exhausted its continuous enclosure budget.") }
        boxes -= 1; visited += 1
        try charge(scalars: 512, work: 4_096)
    }
    static func product(_ factors: Int...) throws -> Int {
        var value = 1
        for factor in factors {
            let result = value.multipliedReportingOverflow(by: factor)
            guard factor >= 0, !result.overflow else { throw GeometryConversionError.resourceLimitExceeded("Conversion dimension arithmetic overflowed.") }
            value = result.partialValue
        }
        return value
    }
}
