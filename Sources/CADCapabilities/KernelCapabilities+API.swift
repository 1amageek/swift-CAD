import CADCore

extension KernelCapabilities {
  static let apiCapabilities: [KernelCapability] = [
    KernelCapability(
      id: "API-PARITY-001",
      operation: "CADCommand",
      status: .supported,
      topology: .document,
      acceptedInputs: ["UI", "Builder", "Agent"],
      exactOutputs: [
        "CADDocument",
        "typedDocumentAttributeEditsWithLocalReferenceIntegrity",
        "KernelQueryResult",
        "snapMeasurementAndSelectionResults",
        "curveEdgeAndSurfaceProjectionResults",
        "diagnostics",
        "strictCodableKernelQueryResults",
        "transportValidatedEvaluatedDocumentAndDerivedResultInvariants",
      ],
      failureCodes: [
        .invalidInput,
        .missingReference,
        .ambiguousSelection,
        .resourceLimitExceeded,
        .topologyFailure,
        .cancelled,
        .unclassifiedFailure,
      ],
      tolerance: .standard,
      publicAPIs: [
        "CADCore.KernelError.wrapping",
        "CADCore.KernelFailureCategory",
        "CADCore.KernelCapabilityCatalog.domain",
        "CADCore.KernelCapabilityDomain",
        "CADCore.KernelDomainLimitation",
        "CADIR.CADCommand",
        "CADIR.DocumentFoundation",
        "CADIR.DocumentReferenceResolving",
        "SwiftCAD.DocumentEditing",
        "SwiftCAD.DocumentEditor",
        "SwiftCAD.CADPipeline",
        "CADKernel.KernelQuery",
        "CADKernel.KernelQueryResult",
        "CADKernel.KernelQueryResult.validate",
        "CADKernel.ProjectionQuery",
        "CADKernel.ProjectionQueryResult",
        "CADKernel.EvaluatedDocument",
        "CADKernel.EvaluationReport",
      ],
      testFixtures: [
        "KernelFailureContractTests",
        "KernelFailurePipelineTests",
        "KernelCapabilityDomainTests",
        "KernelCapabilityDomainPipelineTests",
        "CADCommandPipelineTests",
        "DocumentFoundationTests",
        "DocumentFoundationCommandTests",
        "KernelQueryPipelineTests",
        "StrictCurrentKernelQuerySchemaTests",
      ]
    ),
    KernelCapability(
      id: "API-TRANSACTION-001",
      operation: "documentTransaction",
      status: .supported,
      topology: .document,
      acceptedInputs: [
        "nonemptyExactEvaluatableDocument", "orderedCADCommandBatches",
        "injectedDocumentEditorAndExactEvaluator", "explicitHistoryAndCommandLimits",
        "sessionOwnedTokenAndMonotonicEpoch",
      ],
      exactOutputs: [
        "atomicSourceAndExactEvaluationPublication", "rollbackWithoutPublication",
        "completeSourceEvaluationAndStableIdentityUndoRedo",
        "preservedReferenceDependencyAttributeAndParameterSnapshots",
        "failedStageCommitOrCancellationPreservesCommittedStateAndHistory",
      ],
      failureCodes: [.invalidInput, .missingReference, .resourceLimitExceeded,
        .emptyResult, .cancelled, .topologyFailure],
      tolerance: .standard,
      publicAPIs: [
        "SwiftCAD.DocumentTransacting", "SwiftCAD.DocumentTransactionSession",
        "SwiftCAD.DocumentTransactionToken", "SwiftCAD.DocumentTransactionLimits",
        "SwiftCAD.DocumentTransactionError", "SwiftCAD.DocumentTransactionSnapshot",
      ],
      testFixtures: ["DocumentTransactionTests"]
    )
  ]
}
