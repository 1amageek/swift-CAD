import CADCore

extension KernelCapabilities {
    static let modelingSurfaceFoundationCapabilities: [KernelCapability] = [
        feature(
            id: "MODEL-POLYSPLINE-001",
            operation: "polySpline",
            topology: .sheetBody,
            inputs: [
                "finiteConnectedManifoldTriangulatedRectangularQuadGrid",
                "completeDeterministicTriangleToQuadPartition",
                "intervalCertifiedRegularAndGloballyEmbeddedNaturalBicubicReconstruction",
                "optionalStrictInteriorFinitePositiveWeightControlPointOverrides",
                "optionalExactPiecewiseLinearBoundaryInterpolation",
                "optionalExactRoundedCornerTrims",
                "optionalExactMultiSpanPatchMerge",
            ],
            outputs: [
                "validatedExactSheetBRep",
                "exactNaturalBicubicPatchNetwork",
                "optionalExactMultiSpanMergedSurface",
                "exactRationalRoundedCornerTrims",
                "mandatoryFaceLocalPcurves",
                "generatedTopologyLineage",
            ],
            fixtures: [
                "CADKernelTests.polySplineNonplanarPatchNetworkCreatesC2MultiPatchSheetTopology",
                "CADKernelTests.polySplineMergedPatchNetworkCreatesOneExactMultiSpanFace",
                "CADKernelTests.polySplineRoundedPatchNetworkPreservesSharedInteriorTopology",
                "CADKernelTests.polySplineRoundedMergedPatchNetworkCreatesOneExactTrimmedFace",
                "CADKernelTests.polySplineRejectsControlPointOverridesThatMakeSurfaceSingular",
                "CADKernelTests.polySplineMeshAnalysisRejectsFoldedRectangularPatchGrid",
                "CADKernelTests.polySplineMeshAnalysisPartitionsMoreThan64Candidates",
            ],
            status: .partial,
            failureCodes: [
                .invalidInput,
                .unsupportedCapability,
                .singularGeometry,
                .resourceLimitExceeded,
                .topologyFailure,
                .nonManifoldResult,
            ],
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
