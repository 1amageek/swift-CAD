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
        let capability = try KernelCapabilities.current.requireRegistered(
            operation: "curveSurfaceIntersection"
        )

        #expect(capability.status == .partial)
        #expect(capability.acceptedInputs.contains(
            "certifiedIntersectionCurveAgainstEitherSourceSurface"
        ))
        #expect(capability.exactOutputs.contains(
            "typedContinuousCoincidenceForEveryCertifiedIntersectionCurveKind"
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
        #expect(capability.failureCodes.contains(.unsupportedCapability))
        #expect(capability.testFixtures.contains(
            "CertifiedIntersectionCurveSurfaceIntersectionTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedConeCylinderFullBranchSkewCylinderTests"
        ))
        #expect(capability.testFixtures.contains(
            "CertifiedCylinderCylinderSpatialDifferentialBoundsTests"
        ))
        #expect(capability.testFixtures.contains(
            "ConeCylinderSpherePolynomialBuilderTests"
        ))
    }

    @Test
    func partialCapabilityCannotBeUsedAsSupported() throws {
        let capability = try KernelCapabilities.current.requireRegistered(operation: "sweep")
        #expect(capability.status == .partial)
        #expect(throws: KernelError.self) {
            _ = try KernelCapabilities.current.requireSupported(operation: "sweep")
        }
    }

    @Test
    func boundedSurfaceOperationsRemainPartialUntilGeneralInputsAreImplemented() throws {
        for operation in ["surfaceTrim", "surfaceMatch"] {
            let capability = try KernelCapabilities.current.requireRegistered(
                operation: operation
            )
            #expect(capability.status == .partial)
            #expect(throws: KernelError.self) {
                _ = try KernelCapabilities.current.requireSupported(
                    operation: operation
                )
            }
        }
    }
}
