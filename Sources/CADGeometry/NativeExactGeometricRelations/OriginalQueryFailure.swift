import CADCore

/// Public classification alongside the original typed cause and immutable query authority.
public struct OriginalQueryFailure: KernelFailureClassifying {
    public let originalError: any Error
    public let kernelFailure: KernelError
    public let context: OriginalQueryFailureContext
    @usableFromInline
    init(originalError: any Error, kernelFailure: KernelError, context: OriginalQueryFailureContext) {
        self.originalError = originalError; self.kernelFailure = kernelFailure; self.context = context
    }
    /// Reads only the concrete failure owners supported at this module boundary.
    @_alwaysEmitIntoClient
    public static func classification(of error: any Error) -> KernelError? {
        if let failure = error as? Self { return failure.kernelFailure }
        return error as? KernelError
    }

    public static func published(_ error: any Error, context: OriginalQueryFailureContext,
        tolerance: ModelingTolerance?) -> any Error {
        NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: context)
    }
    /// Adds diagnostic text without replacing the original failure classification.
    public static func contextualizing(_ error: any Error, diagnosticPrefix: String,
        context: OriginalQueryFailureContext, tolerance: ModelingTolerance?) -> any Error {
        let retained = published(error, context: context, tolerance: tolerance)
        if retained is CancellationError { return retained }
        guard let failure = retained as? Self else { return retained }
        let original = failure.kernelFailure
        let classification = KernelError(phase: original.phase, code: original.code,
            featureID: original.featureID, subshapeID: original.subshapeID,
            residual: original.residual, tolerance: original.tolerance,
            message: diagnosticPrefix + original.message)
        return Self(originalError: failure.originalError, kernelFailure: classification,
            context: failure.context)
    }
    public static func contextualizing(_ error: any Error, classification: KernelError) -> any Error {
        let retained = NativeExactGeometryPublicationFailure.published(error, tolerance: classification.tolerance)
        if retained is CancellationError { return retained }
        guard let failure = retained as? Self else { return retained }
        return Self(originalError: failure.originalError, kernelFailure: classification, context: failure.context)
    }
}
