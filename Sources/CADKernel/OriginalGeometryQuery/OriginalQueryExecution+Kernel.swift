import CADGeometry

extension OriginalQueryExecution {
    /// Creates the existing ordinary Kernel envelope at an operation entry.
    static func kernelOriginal(context: OriginalQueryFailureContext = .unspecified)
        throws -> OriginalQueryExecution {
        try .init(budget: OriginalQueryBudget(),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: Int.max, maximumTransportDepth: Int.max,
                maximumSubdivisionDepth: Int.max), context: .init(operation: context.operation,
                entry: context.entry == .unspecified ? .ordinary : context.entry,
                stage: context.stage == .unspecified ? .request : context.stage,
                first: context.first, second: context.second,
                firstOwner: context.firstOwner, secondOwner: context.secondOwner, resource: context.resource))
    }
    /// Debits the typed retained payload at its actual Kernel allocation owner.
    mutating func retainKernelValues(count: Int, stride: Int) throws {
        guard count >= 0, stride >= 0 else { throw ExactScalarFailure.invalidSource }
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
        try retainStorage(bytes: bytes.partialValue)
    }
}
