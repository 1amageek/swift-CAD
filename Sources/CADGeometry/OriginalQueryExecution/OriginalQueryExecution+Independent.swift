import CADCore

extension OriginalQueryExecution {
    public static func independentGeometry(context: OriginalQueryFailureContext = .unspecified)
        throws -> OriginalQueryExecution {
        try .init(budget: OriginalQueryBudget(),
            limits: .init(maximumValueDepth: Int.max, maximumCoefficientDepth: Int.max), context: context)
    }

}
