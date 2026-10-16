import CADCore
import CADGeometry

/// Configures the original source root's immutable accounting and depth authority.
enum IndependentShapeSourceExecutionOwner {
    static func execution(limits: IndependentShapeSourceLimits,
        check: @escaping @Sendable () throws -> Void = {}) throws -> OriginalQueryExecution {
        try limits.validate()
        return try OriginalQueryExecution(
            budget: OriginalQueryBudget(workLimit: limits.maximumWork,
                sourceTextByteLimit: limits.maximumTextBytes, recordLimit: limits.maximumRecords,
                cellVisitRecords: 1, allocationPolicy: .uint32Words, checkpoint: check),
            limits: .init(maximumValueDepth: limits.maximumAlgebraicDepth,
                maximumCoefficientDepth: limits.maximumAlgebraicDepth,
                remainingSourceDepth: limits.maximumDepth,
                maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth))
    }
    static func charge(records: Int = 0, work: Int = 0, textBytes: Int = 0,
        using execution: inout OriginalQueryExecution) throws {
        try execution.chargeSourceText(records: records, work: work, storageBytes: textBytes)
    }
    static func records(_ count: Int, using execution: inout OriginalQueryExecution) throws {
        try charge(records: count, work: count, using: &execution)
    }
    static func text(_ value: String, using execution: inout OriginalQueryExecution) throws {
        let count = value.utf8.count
        try charge(work: count, textBytes: count, using: &execution)
    }
    static func sum(_ a: Int, _ b: Int) throws -> Int {
        let result = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !result.overflow else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Independent source count overflow.")
        }
        return result.partialValue
    }
    static func failure(_ error: any Error) -> any Error {
        if let scalar = error as? ExactScalarFailure {
            switch scalar {
            case .cancelled: return CancellationError()
            case .admissionRejected(let cause): return failure(cause)
            default: return error
            }
        }
        guard let original = error as? OriginalQueryFailure else { return error }
        if let resource = original.context.resource, case .known = resource.used {
            switch resource.axis {
            case .work:
                return IndependentShapeSourceError.resourceLimitExceeded("Independent source cumulative work ceiling.")
            case .sourceRecords:
                return IndependentShapeSourceError.resourceLimitExceeded("Independent source record ceiling.")
            case .sourceTextBytes:
                return IndependentShapeSourceError.resourceLimitExceeded("Independent source UTF8 ceiling.")
            default: break
            }
        }
        return failure(original.originalError)
    }

}
