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
                .unsupportedCapability,
                .ambiguousSelection,
                .resourceLimitExceeded,
                .topologyFailure,
            ],
            tolerance: .standard,
            publicAPIs: [
                "CADIR.CADCommand",
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
                "CADCommandPipelineTests",
                "KernelQueryPipelineTests",
                "StrictCurrentKernelQuerySchemaTests",
            ]
        ),
    ]
}
