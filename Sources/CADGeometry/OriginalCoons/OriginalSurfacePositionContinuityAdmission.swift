import CADCore

/// Retrieves immutable original C0 authority after the caller's source validation.
package struct OriginalSurfacePositionContinuityAdmission {
    package init() {}
    package func provesAssumingSourceValidated<B: RationalAlgebraAdmitting>(_ surface: Surface3D,
        remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
        guard remainingSourceDepth >= 0 else { throw GeometryConversionError.invalidInput("Original surface continuity source cap is invalid.") }
        try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
        switch surface {
        case .procedural(.originalCoons(let source)):
            try source.validate(tolerance:tolerance)
            return source.hasOriginalPositionContinuity
        case .procedural(.originalBoundaryCorrected(let source)):
            try source.validate(tolerance:tolerance)
            return source.hasOriginalPositionContinuity
        case .procedural(.originalPlaneDerivative(let source)):
            try source.validate(tolerance:tolerance)
            return source.hasOriginalPositionContinuity
        default: return false
        }
    }
}
