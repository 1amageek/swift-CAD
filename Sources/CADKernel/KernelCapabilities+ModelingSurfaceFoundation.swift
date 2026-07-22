import CADCore

extension KernelCapabilities {
    static let modelingSurfaceFoundationCapabilities: [KernelCapability] = [
        feature(
            id: "MODEL-POLYSPLINE-001",
            operation: "polySpline",
            topology: .sheetBody,
            inputs: ["supportedQuadMesh"],
            outputs: ["validatedSheet"],
            fixtures: ["CADKernelTests"],
            additionalPublicAPIs: [
                "CADModeling.PolySplineFeatureEvaluator",
                "CADModeling.PolySplineMeshAnalyzer",
            ]
        ),
        feature(
            id: "MODEL-BSPLINESURFACE-001",
            operation: "bSplineSurface",
            topology: .sheetBody,
            inputs: [
                "finitePositiveWeightRationalBSplineSurface",
                "optionalContainedFiniteRectangularParameterDomain",
                "intervalCertifiedRegularRetainedDomain",
                "intervalCertifiedGloballyEmbeddedRetainedDomain",
            ],
            outputs: [
                "validatedExactSheetBRep",
                "exactRationalBSplineSurface",
                "exactIsoparametricBoundaryCurvesAndPcurves",
                "generatedTopologyLineage",
            ],
            fixtures: [
                "SurfaceFeatureEvaluatorTests",
                "CADKernelTests",
                "BSplineSurfaceCommandParityTests",
            ],
            status: .supported,
            failureCodes: [
                .invalidInput,
                .singularGeometry,
                .resourceLimitExceeded,
                .topologyFailure,
            ],
            additionalPublicAPIs: [
                "CADGeometry.BSplineSurfaceRegularityValidator",
                "CADGeometry.BSplineSurfaceEmbeddingValidator",
                "CADModeling.BSplineSurfaceFeatureEvaluator",
            ]
        ),
    ]
}
