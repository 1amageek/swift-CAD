import CADCore

/// Checked scalar dimensions and failure selection; all state belongs to execution.
enum KnotRemovalAllocation {
    static func product(_ a: Int, _ b: Int) throws -> Int {
        let result = a.multipliedReportingOverflow(by: b)
        guard a >= 0, b >= 0, !result.overflow else {
            throw BSplineKnotRemovalError.resourceLimitExceeded
        }
        return result.partialValue
    }

    static func charge(scalars: Int = 0, work: Int = 0,
        using execution: inout OriginalQueryExecution) throws {
        try execution.charge(scalars: scalars, work: work)
    }

    static func rethrowAdmission(_ error: any Error) throws {
        if error is ExactScalarFailure || error is OriginalQueryFailure || error is CancellationError {
            throw error
        }
        if let classification = OriginalQueryFailure.classification(of: error),
            classification.code == .resourceLimitExceeded || classification.code == .cancelled
                || classification.code == .unsupportedCapability || classification.code == .missingReference {
            throw error
        }
    }
}
