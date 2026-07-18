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
        #expect(catalog.capabilities.allSatisfy { $0.publicAPIs.isEmpty == false })
        #expect(catalog.capabilities.allSatisfy { $0.testFixtures.isEmpty == false })
    }

    @Test
    func everyFeatureOperationHasADedicatedCapability() throws {
        for operation in FeatureOperationKind.allCases.map(\.rawValue) {
            let capability = try KernelCapabilities.current.require(operation: operation)
            #expect(capability.operation == operation)
        }
    }
}
