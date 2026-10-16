/// Complete original parameter clipping; image/fiber topology is a separate publication contract.
public protocol OriginalNativeBoundaryClipping: Sendable {
    func clip(_ boundary: OriginalNativeBoundaryDomain, selection: OriginalNativeBoundaryDomain.Selection,
        maximumDepth: Int, maximumCoefficientDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalClippedNativeParameters
}
