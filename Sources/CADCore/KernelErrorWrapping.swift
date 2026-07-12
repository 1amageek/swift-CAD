public extension KernelError {
    /// Converts a legacy domain error into the single error contract exposed by the kernel.
    /// Existing `KernelError` values are preserved so phase and diagnostic details are not lost.
    static func wrapping(
        _ error: Error,
        phase: KernelPhase,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance? = nil
    ) -> KernelError {
        if let kernelError = error as? KernelError {
            return KernelError(
                phase: kernelError.phase,
                code: kernelError.code,
                featureID: kernelError.featureID ?? featureID,
                subshapeID: kernelError.subshapeID,
                residual: kernelError.residual,
                tolerance: kernelError.tolerance ?? tolerance,
                message: kernelError.message
            )
        }

        let code: KernelErrorCode
        switch error {
        case is GeometryError, is UnitError, is ParameterError, is SchemaError:
            code = .invalidInput
        case let featureError as FeatureEvaluationError:
            switch featureError {
            case .missingInput, .missingProfile:
                code = .missingReference
            case .unsupportedOperation:
                code = .unsupportedCapability
            case .emptyResult:
                code = .topologyFailure
            case .invalidGraph, .invalidDistance, .invalidDirection:
                code = .invalidInput
            }
        case let topologyError as TopologyError:
            switch topologyError {
            case .missingReference:
                code = .missingReference
            case .nonManifoldEdge:
                code = .nonManifoldResult
            default:
                code = .topologyFailure
            }
        case is TessellationError, is ExportError, is ImportError:
            code = .invalidInput
        default:
            code = .invalidInput
        }

        return KernelError(
            phase: phase,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: String(describing: error)
        )
    }
}
