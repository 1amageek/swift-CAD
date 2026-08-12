import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Kernel capability contracts")
struct KernelCapabilityContractTests {
    @Test
    func catalogBindsEveryCurrentCapabilityToAPIsAndFixtures() throws {
        let catalog = KernelCapabilities.current
        try catalog.validate()

        let expectedIDs: Set<String> = [
            "GEO-CURVE-001",
            "GEO-CURVE-002",
            "GEO-SURFACE-001",
            "GEO-SURFACE-002",
            "GEO-INTERSECTION-001",
            "GEO-INTERSECTION-002",
            "GEO-PREDICATE-001",
            "TOPO-LINEAGE-001",
            "TOPO-BREP-001",
            "TOPO-SEWING-001",
            "TOPO-REPAIR-001",
            "MODEL-SKETCH-001",
            "MODEL-PRIMITIVE-001",
            "MODEL-EXTRUDE-001",
            "MODEL-REVOLVE-001",
            "MODEL-SWEEP-001",
            "MODEL-LOFT-001",
            "MODEL-BOOLEAN-001",
            "MODEL-POLYSPLINE-001",
            "MODEL-BSPLINESURFACE-001",
            "MODEL-BRIDGESURFACE-001",
            "MODEL-PATCHSURFACE-001",
            "MODEL-FACELOOPOFFSET-001",
            "MODEL-EDGEOFFSET-001",
            "MODEL-FACEKNIFE-001",
            "MODEL-FACEDELETE-001",
            "MODEL-FACEDRAFT-001",
            "MODEL-CHAMFER-001",
            "MODEL-FILLET-001",
            "MODEL-G2BLEND-001",
            "MODEL-SETBACKCORNER-001",
            "MODEL-SHELL-001",
            "MODEL-EDGEMOVE-001",
            "MODEL-VERTEXMOVE-001",
            "MODEL-FACEOFFSET-001",
            "MODEL-FACEMOVE-001",
            "MODEL-LINEARPATTERN-001",
            "MODEL-RADIALPATTERN-001",
            "MODEL-GRIDPATTERN-001",
            "MODEL-CURVEDRIVENPATTERN-001",
            "MODEL-MIRROR-001",
            "MODEL-THICKEN-001",
            "MODEL-BRIDGECURVE-001",
            "MODEL-CURVEEDIT-001",
            "MODEL-CURVEOFFSET-001",
            "MODEL-CURVETRIM-001",
            "MODEL-CURVEEXTEND-001",
            "MODEL-CURVEMATCH-001",
            "MODEL-SURFACEOFFSET-001",
            "MODEL-SURFACETRIM-001",
            "MODEL-SURFACEEXTEND-001",
            "MODEL-SURFACEMATCH-001",
            "API-PARITY-001",
            "EXCHANGE-STEP-001",
            "EXCHANGE-IGES-001",
            "EXCHANGE-USD-001",
        ]
        #expect(Set(catalog.capabilities.map(\.id)) == expectedIDs)
        #expect(Set(catalog.capabilities.map(\.operation)).count == catalog.capabilities.count)
        #expect(catalog.capabilities.allSatisfy {
            $0.topology != .notApplicable || $0.id.hasPrefix("GEO-")
        })
        #expect(catalog.capabilities.allSatisfy { $0.publicAPIs.isEmpty == false })
        #expect(catalog.capabilities.allSatisfy { $0.testFixtures.isEmpty == false })
    }

    @Test
    func everyFeatureOperationHasADedicatedCapability() throws {
        for operation in FeatureOperationKind.allCases.map(\.rawValue) {
            let capability = try KernelCapabilities.current.requireRegistered(operation: operation)
            #expect(capability.operation == operation)
        }
    }

    @Test
    func primitiveCapabilityIsAvailableAsSupported() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "primitive"
        )

        #expect(capability.id == "MODEL-PRIMITIVE-001")
        #expect(capability.status == .supported)
    }

    @Test
    func sketchCapabilityIsAvailableAsSupported() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "sketch"
        )

        #expect(capability.id == "MODEL-SKETCH-001")
        #expect(capability.status == .supported)
    }

    @Test
    func extrudeCapabilityIsAvailableAsSupported() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "extrude"
        )

        #expect(capability.id == "MODEL-EXTRUDE-001")
        #expect(capability.status == .supported)
        #expect(capability.exactOutputs.contains("certifiedExactVolume"))
    }

    @Test
    func revolveCapabilityIsAvailableAsSupported() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "revolve"
        )

        #expect(capability.id == "MODEL-REVOLVE-001")
        #expect(capability.status == .supported)
        #expect(capability.acceptedInputs.contains(
            "planarClosedRationalBSplineProfile"
        ))
        #expect(capability.exactOutputs.contains("certifiedExactVolume"))
        #expect(capability.failureCodes.contains(.classificationFailure))
    }

    @Test
    func exactBRepSewingCapabilityIsAvailableAsSupported() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "exactBRepSewing"
        )

        #expect(capability.id == "TOPO-SEWING-001")
        #expect(capability.exactOutputs.contains("validatedBRepResultType"))
    }

    @Test
    func validatedBRepCapabilityIsAvailableAsSupported() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "validatedBRep"
        )

        #expect(capability.id == "TOPO-BREP-001")
        #expect(capability.exactOutputs.contains(
            "validatedBRepRetainedCertifiedVolume"
        ))
    }

    @Test
    func sweepCapabilityBindsExactPointGuideVerticalSlice() throws {
        let capability = try KernelCapabilities.current.requireRegistered(operation: "sweep")

        #expect(capability.acceptedInputs.contains(
            "zeroGuidesOrOneStraightPointGuideWithVerifiedSectionBoundaryContactAndPositiveSimilarityTransform"
        ))
        #expect(capability.exactOutputs.contains(
            "exactStraightPointGuideSimilaritySectionLaw"
        ))
        #expect(capability.failureCodes.contains(.sweepGuideContactUnavailable))
        #expect(capability.failureCodes.contains(.sweepGuideTransformCollapse))
        #expect(capability.failureCodes.contains(.sweepGuideConstraintUnavailable))
        #expect(capability.testFixtures.contains(
            "ExactPointGuideSweepCommandParityTests"
        ))
    }

    @Test
    func curveSurfaceCapabilityBindsCertifiedCurveEnvelopes() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "curveSurfaceIntersection"
        )

        #expect(capability.status == .supported)
        #expect(capability.acceptedInputs.contains(
            "everyValidatedCurveAndSurfaceRepresentationPair"
        ))
        #expect(capability.failureCodes.contains(.unsupportedCapability) == false)
        #expect(capability.acceptedInputs.contains(
            "certifiedIntersectionCurveAgainstEitherSourceSurface"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedIntersectionCurveAgainstToleranceEquivalentSourceSurfaceRepresentation"
        ))
        #expect(capability.exactOutputs.contains(
            "typedContinuousCoincidenceForEveryCertifiedIntersectionCurveKind"
        ))
        #expect(capability.exactOutputs.contains(
            "typedNonDiscreteSourceCoincidenceAcrossCanonicalAnalyticRepresentations"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedIntersectionCurveAgainstSpatiallySeparatedExactSphereOrTorus"
        ))
        #expect(capability.exactOutputs.contains(
            "outwardRoundedBoundingBoxCertifiedEmptyIntersection"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeBasedIntersectionCurveAgainstExactPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "algebraicallyReducedCertifiedCurvePlaneIntersectionsWithRecoveredSourceParameter"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedParallelTorusTorusIntersectionCurveAgainstExactPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "degreeEightParallelTorusPlaneEliminationWithVerifiedSourceParameter"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedSphereConeIntersectionCurveAgainstExactSphere"
        ))
        #expect(capability.exactOutputs.contains(
            "sphereSectionReducedCertifiedCurveSphereIntersectionsWithRecoveredSourceParameter"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedSphereConeIntersectionCurveAgainstExactCoaxialCylinder"
        ))
        #expect(capability.exactOutputs.contains(
            "coneSectionReducedCertifiedCurveCylinderIntersectionsWithRecoveredSourceParameter"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedSphereConeIntersectionCurveAgainstExactCylinder"
        ))
        #expect(capability.exactOutputs.contains(
            "coneCylinderSectionReducedCertifiedSphereConeCurveCylinderIntersectionsWithCanonicalSourceParameterRecovery"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeCylinderIntersectionCurveAgainstExactCoaxialSphere"
        ))
        #expect(capability.exactOutputs.contains(
            "cylinderSectionReducedCertifiedCurveSphereIntersectionsWithRecoveredSourceParameterAndPoleSafeTargetNormal"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeCylinderIntersectionCurveAgainstExactSphere"
        ))
        #expect(capability.exactOutputs.contains(
            "degreeEightConeCylinderSphereResultantWithVerifiedSourceParameter"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeCylinderIntersectionCurveAgainstNonDegenerateExactCone"
        ))
        #expect(capability.exactOutputs.contains(
            "degreeSixteenConeCylinderConeResultantWithVerifiedSourceParameterAndTangency"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeConeIntersectionCurveAgainstExactCylinderWithNonDegenerateConeCylinderConeReduction"
        ))
        #expect(capability.exactOutputs.contains(
            "coneCylinderSectionReducedCertifiedConeConeCurveCylinderIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedSphereConeIntersectionCurveAgainstNonDegenerateExactCone"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeConeIntersectionCurveAgainstNonDegenerateExactSphere"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeConeIntersectionCurveAgainstNonDegenerateExactCone"
        ))
        #expect(capability.exactOutputs.contains(
            "degreeSixteenConeHostedQuadricResultantWithVerifiedSourceParameterAndTangency"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeCylinderIntersectionCurveAgainstExactParallelAxisCylinder"
        ))
        #expect(capability.exactOutputs.contains(
            "parallelCylinderGeneratorReducedCertifiedCurveCylinderIntersectionsWithRecoveredSourceParameter"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeCylinderIntersectionCurveAgainstExactFullBranchSkewCylinder"
        ))
        #expect(capability.exactOutputs.contains(
            "fullBranchCylinderPairReducedCertifiedCurveCylinderIntersectionsWithStructuralDifferentialBounds"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedConeCylinderIntersectionCurveAgainstExactBoundedSkewCylinder"
        ))
        #expect(capability.exactOutputs.contains(
            "boundedCylinderPairReducedCertifiedCurveCylinderIntersectionsWithEndpointRegularizedIntervalDifferentialBounds"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedReducedSectionWithAlgebraicallyIdentifiedComponent"
        ))
        #expect(capability.exactOutputs.contains(
            "bezoutCertifiedReducedSectionComponentCoincidenceAndSharedNodePreservation"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedBoundedPlaneConeSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "boundedConicSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRootFreeSphereCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "rootFreeSphereCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedEndpointRegularizedBoundedSphereCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "endpointRegularizedBoundedSphereCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedPoleSplitSphereCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "poleSplitSphereCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRootFreeSphereConeSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "rootFreeSphereConeSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRootFreeConeCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "rootFreeConeCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRulingParallelConeCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "rulingParallelConeCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedEndpointRegularizedBoundedConeCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "endpointRegularizedBoundedConeCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedMixedRootApexNodeConeCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "mixedRootApexNodeConeCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRootFreeConeConeSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "rootFreeConeConeSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedApexReducedConeConeSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "apexReducedConeConeSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedEndpointRegularizedBoundedConeConeSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "endpointRegularizedBoundedConeConeSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedCoefficientSeparatedRootFreePlaneTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "rootFreePlaneTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedEndpointRegularizedBoundedPlaneTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "endpointRegularizedBoundedPlaneTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedCongruentTorusTorusFullBisectorSectionSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "congruentTorusTorusBisectorSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRootFreeParallelTorusCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "parallelTorusCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedEndpointRegularizedBoundedParallelTorusCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "endpointRegularizedBoundedParallelTorusCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedInternalTangencyParallelTorusCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "internalTangencyParallelTorusCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedSimpleGeneralTorusCylinderSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "generalTorusCylinderSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedSimpleRegularGeneralConeTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "regularGeneralConeTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRootFreeSphereTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "sphereTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedEndpointRegularizedBoundedSphereTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "endpointRegularizedBoundedSphereTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedPoleSplitSphereTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "poleSplitSphereTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedRegularParallelTorusTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "regularParallelTorusTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.acceptedInputs.contains(
            "certifiedSimpleGeneralTorusTorusSurfaceLiftAgainstExactAnalyticPlane"
        ))
        #expect(capability.exactOutputs.contains(
            "generalTorusTorusSpatialDifferentialCertifiedCurvePlaneIntersections"
        ))
        #expect(capability.failureCodes.contains(.unsupportedCapability) == false)
        #expect(capability.testFixtures.contains(
            "CertifiedIntersectionCurveSurfaceIntersectionTests"
        ))
        #expect(capability.testFixtures.contains(
            "AnalyticSurfaceEquivalenceResolverTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedConeCylinderFullBranchSkewCylinderTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedCylinderCylinderSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedSphereCylinderSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedSphereConeSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedConeCylinderSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedConeConeSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedPlaneTorusSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedCongruentTorusTorusSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedParallelTorusCylinderSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedGeneralTorusCylinderSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedGeneralConeTorusSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedSphereTorusSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedParallelTorusTorusSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedGeneralTorusTorusSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "ConeCylinderSpherePolynomialBuilderTests"
        ))
    }

    @Test
    func surfaceSurfaceCapabilityCoversEveryValidatedRepresentationPair() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "surfaceSurfaceIntersection"
        )

        #expect(capability.status == .supported)
        #expect(capability.acceptedInputs.contains(
            "everyValidatedSurfaceRepresentationPair"
        ))
        #expect(capability.failureCodes.contains(.unsupportedCapability) == false)
    }

    @Test
    func partialCapabilityIsExecutableButCannotBeUsedAsSupported() throws {
        let capability = try KernelCapabilities.current.requireRegistered(operation: "sweep")
        #expect(capability.status == .partial)
        #expect(try KernelCapabilities.current.requireExecutable(operation: "sweep")
            == capability)
        #expect(throws: KernelError.self) {
            _ = try KernelCapabilities.current.requireSupported(operation: "sweep")
        }
    }

    @Test
    func plannedCapabilityCannotBeUsedAsExecutable() throws {
        let planned = KernelCapability(
            id: "PLANNED-TEST",
            operation: "plannedOperation",
            status: .planned,
            topology: .solidBody,
            acceptedInputs: ["plannedInput"],
            exactOutputs: ["plannedOutput"],
            failureCodes: [.unsupportedCapability],
            tolerance: .standard,
            publicAPIs: ["PlannedOperation"],
            testFixtures: ["PlannedOperationTests"]
        )
        let catalog = KernelCapabilityCatalog(capabilities: [planned])

        #expect(throws: KernelError.self) {
            _ = try catalog.requireExecutable(operation: planned.operation)
        }
    }

    @Test
    func boundedSurfaceOperationsAreSupportedWithinTheirExactInputContracts() throws {
        for operation in [
            "surfaceOffset",
            "surfaceTrim",
            "surfaceExtend",
            "surfaceMatch",
        ] {
            let capability = try KernelCapabilities.current.requireSupported(
                operation: operation
            )
            #expect(capability.status == .supported)
            #expect(capability.exactOutputs.contains(
                "deterministicStableFaceResolutionWithoutImplicitFaceSelection"
            ))
            #expect(capability.failureCodes.contains(.unsupportedCapability))
        }
        for operation in ["surfaceOffset", "surfaceTrim", "surfaceExtend"] {
            let capability = try KernelCapabilities.current.requireSupported(
                operation: operation
            )
            #expect(capability.acceptedInputs.contains(
                "explicitStableSelectedFaceOwnedByReferencedSheetBody"
            ))
        }
        let trim = try KernelCapabilities.current.requireSupported(
            operation: "surfaceTrim"
        )
        #expect(trim.acceptedInputs.contains(
            "explicitStableSelectedFaceOwnedByReferencedSheetBody"
        ))
        let match = try KernelCapabilities.current.requireSupported(
            operation: "surfaceMatch"
        )
        #expect(match.acceptedInputs.contains(
            "explicitStableSelectedFacesOwnedByReferencedSheetBodies"
        ))
    }

    @Test
    func boundedFaceLoopOffsetIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "faceLoopOffset"
        )

        #expect(capability.status == .supported)
        #expect(capability.acceptedInputs.contains(
            "oneStableSelectedStrictlyConvexLineOnlyPlanarFace"
        ))
        #expect(capability.exactOutputs.contains("preservedAnalyticVolume"))
        #expect(capability.failureCodes.contains(.classificationFailure))
        #expect(capability.failureCodes.contains(.unsupportedCapability))
    }

    @Test
    func boundedEdgeOffsetIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "edgeOffset"
        )

        #expect(capability.status == .supported)
        #expect(capability.topology == .solidBody)
        #expect(capability.acceptedInputs.contains(
            "optionalSymmetricSplitAcrossUniqueOppositeSupportFace"
        ))
        #expect(capability.exactOutputs.contains("preservedAnalyticVolume"))
        #expect(capability.failureCodes.contains(.classificationFailure))
        #expect(capability.failureCodes.contains(.unsupportedCapability))
    }

    @Test
    func boundedFaceKnifeIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "faceKnife"
        )

        #expect(capability.status == .supported)
        #expect(capability.acceptedInputs.contains(
            "oneCoplanarStrictlyInteriorSimpleLineKnifeLoopIncludingConcaveLoops"
        ))
        #expect(capability.exactOutputs.contains(
            "typedAmbiguousSourceFaceSelectionAfterSplit"
        ))
        #expect(capability.failureCodes.contains(.ambiguousSelection))
        #expect(capability.failureCodes.contains(.classificationFailure))
        #expect(capability.failureCodes.contains(.unsupportedCapability))
    }

    @Test
    func boundedFaceDeleteIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "faceDelete"
        )

        #expect(capability.status == .supported)
        #expect(capability.topology == .sheetBody)
        #expect(capability.acceptedInputs.contains(
            "atLeastOneRemainingFaceInEverySourceShell"
        ))
        #expect(capability.exactOutputs.contains(
            "deterministicEdgeConnectedShellPartition"
        ))
        #expect(capability.exactOutputs.contains("orphanFreeTopologyAndGeometry"))
        #expect(capability.failureCodes.contains(.unsupportedCapability))
    }

    @Test
    func boundedFaceDraftIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "faceDraft"
        )

        #expect(capability.status == .supported)
        #expect(capability.topology == .solidBody)
        #expect(capability.acceptedInputs.contains(
            "finiteNonzeroSignedIncrementalAngleBelowNinetyDegrees"
        ))
        #expect(capability.exactOutputs.contains("verifiedConstraintResiduals"))
        #expect(capability.exactOutputs.contains(
            "preservedUnrelatedBodiesAndSelections"
        ))
        #expect(capability.failureCodes.contains(.missingReference))
        #expect(capability.failureCodes.contains(.singularSystem))
        #expect(capability.failureCodes.contains(.conflictingConstraints))
        #expect(capability.failureCodes.contains(.unsupportedCapability))
    }

    @Test
    func boundedChamferIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "chamfer"
        )

        #expect(capability.status == .supported)
        #expect(capability.topology == .solidBody)
        #expect(capability.acceptedInputs.contains(
            "singleStraightEdgeOwnedByTargetBody"
        ))
        #expect(capability.exactOutputs.contains("targetBodyScopedLineageParents"))
        #expect(capability.exactOutputs.contains(
            "typedAmbiguousSourceEdgeSelectionAfterSplit"
        ))
        #expect(capability.failureCodes.contains(.missingReference))
        #expect(capability.failureCodes.contains(.topologyFailure))
        #expect(capability.failureCodes.contains(.ambiguousSelection))
    }

    @Test
    func boundedEdgeBlendsAreSupportedWithinTheirExactInputContracts() throws {
        for operation in ["fillet", "g2Blend"] {
            let capability = try KernelCapabilities.current.requireSupported(
                operation: operation
            )
            #expect(capability.status == .supported)
            #expect(capability.topology == .solidBody)
            #expect(capability.acceptedInputs.contains(
                "singleStraightConvexEdgeOwnedByTargetBody"
            ))
            #expect(capability.exactOutputs.contains(
                "targetBodyScopedLineageParents"
            ))
            #expect(capability.exactOutputs.contains(
                "typedAmbiguousSourceEdgeSelectionAfterSplit"
            ))
            #expect(capability.testFixtures.contains("EdgeBlendOwnershipTests"))
            #expect(capability.failureCodes.contains(.missingReference))
            #expect(capability.failureCodes.contains(.topologyFailure))
            #expect(capability.failureCodes.contains(.ambiguousSelection))
        }
    }

    @Test
    func boundedSetbackCornerIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "setbackCorner"
        )
        #expect(capability.status == .supported)
        #expect(capability.topology == .solidBody)
        #expect(capability.acceptedInputs.contains(
            "oneTargetBodyOwnedTrihedralConvexVertex"
        ))
        #expect(capability.exactOutputs.contains(
            "targetBodyScopedLineageParents"
        ))
        #expect(capability.exactOutputs.contains(
            "typedAmbiguousSourceVertexSelectionAfterSplit"
        ))
        #expect(capability.testFixtures.contains("SetbackCornerOwnershipTests"))
        #expect(capability.failureCodes.contains(.missingReference))
        #expect(capability.failureCodes.contains(.unsupportedCapability))
        #expect(capability.failureCodes.contains(.topologyFailure))
        #expect(capability.failureCodes.contains(.ambiguousSelection))
    }

    @Test
    func boundedShellIsSupportedWithinItsExactInputContract() throws {
        let capability = try KernelCapabilities.current.requireSupported(
            operation: "shell"
        )
        #expect(capability.status == .supported)
        #expect(capability.topology == .solidBody)
        #expect(capability.acceptedInputs.contains(
            "oneTargetBodyOwnedRemovedPlanarFace"
        ))
        #expect(capability.exactOutputs.contains("targetBodyScopedCavityDepth"))
        #expect(capability.exactOutputs.contains(
            "targetBodyScopedLineageParents"
        ))
        #expect(capability.exactOutputs.contains(
            "typedAmbiguousRemovedFaceSelectionAfterSplit"
        ))
        #expect(capability.testFixtures.contains("ShellOwnershipTests"))
        #expect(capability.failureCodes.contains(.missingReference))
        #expect(capability.failureCodes.contains(.unsupportedCapability))
        #expect(capability.failureCodes.contains(.topologyFailure))
        #expect(capability.failureCodes.contains(.ambiguousSelection))
    }

    @Test
    func boundedDirectMovesAreSupportedWithinTheirExactInputContracts() throws {
        let edgeMove = try KernelCapabilities.current.requireSupported(
            operation: "edgeMove"
        )
        #expect(edgeMove.status == .supported)
        #expect(edgeMove.topology == .solidBody)
        #expect(edgeMove.acceptedInputs.contains("oneTargetBodyOwnedStraightEdge"))
        #expect(edgeMove.exactOutputs.contains("targetBodyScopedIdentityReplacement"))
        #expect(edgeMove.exactOutputs.contains("targetBodyScopedLineageParents"))
        #expect(edgeMove.exactOutputs.contains("stableMovedEdgeSelection"))
        #expect(edgeMove.failureCodes.contains(.missingReference))
        #expect(edgeMove.failureCodes.contains(.unsupportedCapability))
        #expect(edgeMove.failureCodes.contains(.topologyFailure))

        let vertexMove = try KernelCapabilities.current.requireSupported(
            operation: "vertexMove"
        )
        #expect(vertexMove.status == .supported)
        #expect(vertexMove.topology == .solidBody)
        #expect(vertexMove.acceptedInputs.contains("oneTargetBodyOwnedVertex"))
        #expect(vertexMove.exactOutputs.contains("targetBodyScopedIdentityReplacement"))
        #expect(vertexMove.exactOutputs.contains("targetBodyScopedLineageParents"))
        #expect(vertexMove.exactOutputs.contains("stableMovedVertexSelection"))
        #expect(vertexMove.failureCodes.contains(.missingReference))
        #expect(vertexMove.failureCodes.contains(.unsupportedCapability))
        #expect(vertexMove.failureCodes.contains(.topologyFailure))
    }

    @Test
    func boundedFaceDirectEditsAreSupportedWithinTheirExactInputContracts() throws {
        let faceOffset = try KernelCapabilities.current.requireSupported(
            operation: "faceOffset"
        )
        #expect(faceOffset.status == .supported)
        #expect(faceOffset.topology == .solidBody)
        #expect(faceOffset.acceptedInputs.contains("oneTargetBodyOwnedPlanarFace"))
        #expect(faceOffset.exactOutputs.contains("targetBodyScopedIdentityReplacement"))
        #expect(faceOffset.exactOutputs.contains("targetBodyScopedLineageParents"))
        #expect(faceOffset.exactOutputs.contains("stableOffsetFaceSelection"))
        #expect(faceOffset.failureCodes.contains(.missingReference))
        #expect(faceOffset.failureCodes.contains(.unsupportedCapability))
        #expect(faceOffset.failureCodes.contains(.topologyFailure))

        let faceMove = try KernelCapabilities.current.requireSupported(
            operation: "faceMove"
        )
        #expect(faceMove.status == .supported)
        #expect(faceMove.topology == .solidBody)
        #expect(faceMove.acceptedInputs.contains("oneTargetBodyOwnedPlanarFace"))
        #expect(faceMove.exactOutputs.contains("targetBodyScopedIdentityReplacement"))
        #expect(faceMove.exactOutputs.contains("targetBodyScopedLineageParents"))
        #expect(faceMove.exactOutputs.contains("stableMovedFaceSelection"))
        #expect(faceMove.failureCodes.contains(.missingReference))
        #expect(faceMove.failureCodes.contains(.unsupportedCapability))
        #expect(faceMove.failureCodes.contains(.topologyFailure))
    }
}
