struct KnotRemovalBudget {
    private var scalars: Int
    private var work: Int

    init(_ options: BSplineKnotRemovalOptions) throws {
        guard options.maximumGeneratedScalarCount > 0, options.maximumWork > 0 else {
            throw BSplineKnotRemovalError.invalidInput("Knot removal requires positive resource budgets.")
        }
        scalars = options.maximumGeneratedScalarCount
        work = options.maximumWork
    }

    static func product(_ a: Int, _ b: Int) throws -> Int {
        let result = a.multipliedReportingOverflow(by: b)
        guard a >= 0, b >= 0, !result.overflow else {
            throw BSplineKnotRemovalError.resourceLimitExceeded
        }
        return result.partialValue
    }

    mutating func charge(scalars count: Int = 0, work operations: Int = 0) throws {
        guard count >= 0, operations >= 0, count <= scalars, operations <= work else {
            throw BSplineKnotRemovalError.resourceLimitExceeded
        }
        scalars -= count
        work -= operations
    }
}
