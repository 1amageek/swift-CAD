public extension KernelError {
    /// Reads a known failure's witness without runtime protocol discovery.
    static func wrapping(
        _ error: any KernelFailureClassifying,
        phase: KernelPhase,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance?
    ) -> KernelError {
        fillingMissingContext(error.kernelFailure, featureID: featureID, tolerance: tolerance)
    }

    @usableFromInline
    internal static func fillingMissingContext(
        _ error: KernelError,
        featureID: FeatureID?,
        tolerance: ModelingTolerance?
    ) -> KernelError {
        KernelError(
            phase: error.phase,
            code: error.code,
            featureID: error.featureID ?? featureID,
            subshapeID: error.subshapeID,
            residual: error.residual,
            tolerance: error.tolerance ?? tolerance,
            message: error.message
        )
    }

    /// Converts a domain error into the single error contract exposed by the kernel.
    /// Existing `KernelError` values are preserved so phase and diagnostic details are not lost.
    @_alwaysEmitIntoClient
    static func wrapping(
        _ error: any Error,
        phase: KernelPhase,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance?
    ) -> KernelError {
        if let kernelError = error as? KernelError {
            return fillingMissingContext(kernelError, featureID: featureID, tolerance: tolerance)
        }

        let code: KernelErrorCode
        switch error {
        case is GeometryError, is UnitError, is MaterialError, is MeshArtifactPurposeError:
            code = .invalidInput
        case let encodingError as PortableSourceEncodingError:
            switch encodingError {
            case .resourceLimitExceeded:
                code = .resourceLimitExceeded
            case .invalidLimits, .nonfiniteScalar, .canonicalKeyCollision:
                code = .invalidInput
            }
        #if !hasFeature(Embedded)
        case is DecodingError, is EncodingError:
            code = .invalidInput
        #endif
        case let schemaError as SchemaError:
            switch schemaError {
            case .unsupportedVersion:
                code = .unsupportedCapability
            case .invalidRevision, .invalidMetadata, .missingRequiredField,
                 .unknownDiscriminator, .invalidPackage:
                code = .invalidInput
            }
        case let parameterError as ParameterError:
            switch parameterError {
            case .unknownReference, .unknownVariable:
                code = .missingReference
            case .invalidName, .duplicateName, .tableKeyMismatch, .cycleDetected, .kindMismatch:
                code = .invalidInput
            }
        case let cacheError as CacheValidationError:
            switch cacheError {
            case .missingBRepCache:
                code = .missingReference
            case .meshCacheExceedsLimits:
                code = .resourceLimitExceeded
            case .staleBRepCache, .staleMeshCache, .meshCachePurposeMismatch:
                code = .invalidInput
            }
        case let sketchError as SketchError:
            switch sketchError {
            case .unsupportedEntity, .unsupportedProfile:
                code = .unsupportedCapability
            case .disconnectedCurveChain:
                code = .invalidInput
            case .invalidReference:
                code = .missingReference
            case .openProfile,
                 .degenerateProfile,
                 .emptyProfile,
                 .unresolvedExpression:
                code = .invalidInput
            }
        case let featureError as FeatureEvaluationError:
            switch featureError {
            case .missingInput, .missingProfile:
                code = .missingReference
            case .emptyResult:
                code = .emptyResult
            case .invalidGraph, .invalidDistance, .invalidDirection:
                code = .invalidInput
            }
        case let topologyError as TopologyError:
            switch topologyError {
            case .missingReference, .missingSurface:
                code = .missingReference
            case .nonManifoldEdge:
                code = .nonManifoldResult
            default:
                code = .topologyFailure
            }
        case let tessellationError as TessellationError:
            switch tessellationError {
            case .invalidTolerance, .invalidLimit, .invalidUsage:
                code = .invalidInput
            case .unsupportedFace:
                code = .unsupportedCapability
            case .degenerateFace:
                code = .singularGeometry
            case .resourceExhausted:
                code = .resourceLimitExceeded
            }
        case let exportError as ExportError:
            switch exportError {
            case .emptyMesh:
                code = .emptyResult
            case .invalidMesh:
                code = .invalidInput
            case .unsupportedFeature:
                code = .unsupportedCapability
            case .triangleCountOverflow:
                code = .resourceLimitExceeded
            case .fileWriteFailure:
                code = .ioFailure
            case .externalToolUnavailable:
                code = .dependencyUnavailable
            case .externalToolFailure:
                code = .externalFailure
            }
        case let importError as ImportError:
            switch importError {
            case .unsupportedFormat, .unsupportedFeature, .unsupportedVersion:
                code = .unsupportedCapability
            case .invalidData, .formatConstraint, .compositionFailure:
                code = .invalidInput
            case .missingRequiredEntity:
                code = .missingReference
            case .securityViolation:
                code = .securityViolation
            case .resourceUnavailable:
                code = .dependencyUnavailable
            case .fileReadFailure:
                code = .ioFailure
            }
        case is CancellationError:
            code = .cancelled
        default:
            code = .unclassifiedFailure
        }

        #if hasFeature(Embedded)
        let message = KernelDomainErrorPresentation.message(for: error)
        #else
        let message = String(describing: error)
        #endif

        return KernelError(
            phase: phase,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
