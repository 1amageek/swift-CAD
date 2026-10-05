public enum KernelErrorCode: String, Hashable, Sendable, CaseIterable {
    case invalidInput
    case missingReference
    case unsupportedCapability
    case sweepSimplifyUnavailable
    case sweepProfilePlaneDegenerate
    case sweepMixedNormalAdvance
    case sweepMonotonicityCertificateUnavailable
    case sweepBooleanRequiresSolid
    case sweepInvalidGuideConstraintCount
    case sweepRoundCornerUnavailable
    case sweepPathNormalUnavailable
    case sweepScaleCollapse
    case sweepScalePathUnavailable
    case sweepTwistUnavailable
    case sweepGuideContactUnavailable
    case sweepGuideTransformCollapse
    case sweepGuideConstraintUnavailable
    case ambiguousSelection
    case underConstrained
    case overConstrained
    case conflictingConstraints
    case singularSystem
    case singularGeometry
    case intersectionFailure
    case nonDiscreteIntersection
    case classificationFailure
    case approximationToleranceRejected
    case emptyResult
    case topologyFailure
    case filletThicknessExceeded
    case filletSelfIntersection
    case filletFaceDisappeared
    case nonManifoldResult
    case resourceLimitExceeded
    case cancelled
    case ioFailure
    case dependencyUnavailable
    case externalFailure
    case securityViolation
    case unclassifiedFailure

    public var category: KernelFailureCategory {
        switch self {
        case .invalidInput, .sweepInvalidGuideConstraintCount,
             .sweepBooleanRequiresSolid, .sweepMixedNormalAdvance, .filletThicknessExceeded:
            .invalidInput
        case .missingReference:
            .missingReference
        case .unsupportedCapability, .sweepSimplifyUnavailable, .sweepRoundCornerUnavailable,
             .sweepScalePathUnavailable, .sweepTwistUnavailable,
             .sweepGuideContactUnavailable, .sweepGuideConstraintUnavailable:
            .unsupportedDomain
        case .ambiguousSelection, .sweepPathNormalUnavailable:
            .ambiguity
        case .underConstrained, .overConstrained, .conflictingConstraints:
            .constraintFailure
        case .singularSystem, .singularGeometry, .sweepProfilePlaneDegenerate,
             .sweepScaleCollapse, .sweepGuideTransformCollapse:
            .singularity
        case .intersectionFailure, .classificationFailure, .approximationToleranceRejected,
             .sweepMonotonicityCertificateUnavailable:
            .numericalIndeterminacy
        case .nonDiscreteIntersection:
            .nonDiscreteResult
        case .emptyResult:
            .emptyResult
        case .topologyFailure, .nonManifoldResult, .filletSelfIntersection, .filletFaceDisappeared:
            .invalidTopology
        case .resourceLimitExceeded:
            .resourceExhaustion
        case .cancelled:
            .cancelled
        case .ioFailure:
            .ioFailure
        case .dependencyUnavailable:
            .dependencyUnavailable
        case .externalFailure:
            .externalFailure
        case .securityViolation:
            .securityRefusal
        case .unclassifiedFailure:
            .unclassified
        }
    }
}

#if !hasFeature(Embedded)
extension KernelErrorCode: Codable {}
#endif
