import CADCore

public enum KernelCapabilities {
    public static let current = KernelCapabilityCatalog(capabilities: [
        KernelCapability(
            id: "GEO-CURVE-001",
            operation: "analyticCurve",
            status: .supported,
            acceptedInputs: ["line", "circle", "arc", "ellipse", "rationalBezier", "rationalNURBS"],
            exactOutputs: ["position", "firstDerivative", "secondDerivative", "tangent", "curvature"],
            failureCodes: [.invalidInput]
        ),
        KernelCapability(
            id: "GEO-CURVE-002",
            operation: "rationalBSplineCurve",
            status: .supported,
            acceptedInputs: ["controlPoints", "weights", "knots", "degree"],
            exactOutputs: ["position", "firstDerivative", "secondDerivative", "curvature"],
            failureCodes: [.invalidInput]
        ),
        KernelCapability(
            id: "GEO-SURFACE-001",
            operation: "analyticSurface",
            status: .supported,
            acceptedInputs: ["plane", "cylinder", "cone", "sphere", "torus"],
            exactOutputs: [
                "position", "tangentU", "tangentV", "secondDerivatives", "normal",
                "curvature", "principalDirections", "UVNFrame",
            ],
            failureCodes: [.invalidInput]
        ),
        KernelCapability(
            id: "GEO-SURFACE-002",
            operation: "rationalBSplineSurface",
            status: .partial,
            acceptedInputs: ["controlNet", "weights", "knotsU", "knotsV", "degreeU", "degreeV"],
            exactOutputs: [
                "position", "tangentU", "tangentV", "secondDerivatives", "normal",
                "curvature", "principalDirections", "UVNFrame",
            ],
            failureCodes: [.invalidInput, .topologyFailure]
        ),
        KernelCapability(
            id: "TOPO-LINEAGE-001",
            operation: "topologyLineage",
            status: .partial,
            acceptedInputs: ["generatedFeatureOutput"],
            exactOutputs: ["SubshapeID", "TopologyLineage"],
            failureCodes: [.missingReference, .ambiguousSelection, .topologyFailure]
        ),
        KernelCapability(
            id: "TOPO-BREP-001",
            operation: "validatedBRep",
            status: .partial,
            acceptedInputs: ["vertex", "edge", "coedge", "loop", "face", "shell", "body"],
            exactOutputs: ["manifold", "watertight", "validatedTopology"],
            failureCodes: [.invalidInput, .missingReference, .topologyFailure, .nonManifoldResult]
        ),
        KernelCapability(
            id: "MODEL-EXTRUDE-001",
            operation: "extrude",
            status: .partial,
            acceptedInputs: ["planarProfile"],
            exactOutputs: ["validatedBRep"],
            failureCodes: [.invalidInput, .unsupportedCapability, .topologyFailure]
        ),
        KernelCapability(
            id: "MODEL-FEATURE-001",
            operation: "featureOperation",
            status: .partial,
            acceptedInputs: ["validatedFeatureRequest"],
            exactOutputs: ["validatedBRep", "validatedCurve", "validatedSheet"],
            failureCodes: [.invalidInput, .missingReference, .unsupportedCapability, .topologyFailure]
        ),
        KernelCapability(
            id: "MODEL-BOOLEAN-001",
            operation: "boolean",
            status: .partial,
            acceptedInputs: ["axisAlignedBoxSolid"],
            exactOutputs: ["validatedBRep"],
            failureCodes: [.invalidInput, .unsupportedCapability, .topologyFailure, .nonManifoldResult]
        ),
        KernelCapability(
            id: "MODEL-FILLET-001",
            operation: "fillet",
            status: .planned,
            acceptedInputs: ["validatedBRep", "edgeSelection", "radius"],
            exactOutputs: ["trimmedSurfaces", "validatedBRep", "TopologyLineage"],
            failureCodes: [.invalidInput, .unsupportedCapability, .intersectionFailure, .topologyFailure]
        ),
        KernelCapability(
            id: "MODEL-SHELL-001",
            operation: "shell",
            status: .planned,
            acceptedInputs: ["validatedBRep", "faceSelection", "thickness"],
            exactOutputs: ["offsetSurfaces", "validatedBRep", "TopologyLineage"],
            failureCodes: [.invalidInput, .unsupportedCapability, .intersectionFailure, .topologyFailure]
        ),
        KernelCapability(
            id: "API-PARITY-001",
            operation: "CADCommand",
            status: .partial,
            acceptedInputs: ["UI", "Builder", "Agent"],
            exactOutputs: ["CADDocument", "diagnostics"],
            failureCodes: [.invalidInput, .missingReference, .unsupportedCapability]
        ),
        KernelCapability(
            id: "EXCHANGE-STEP-001",
            operation: "STEP",
            status: .partial,
            acceptedInputs: ["validatedBRep"],
            exactOutputs: ["analyticCurves", "analyticSurfaces", "pcurves", "validatedTopology"],
            failureCodes: [.unsupportedCapability, .resourceLimitExceeded]
        ),
        KernelCapability(
            id: "EXCHANGE-IGES-001",
            operation: "IGES",
            status: .partial,
            acceptedInputs: ["validatedBRep"],
            exactOutputs: ["analyticCurves", "analyticSurfaces", "trimmedSurfaces", "validatedTopology"],
            failureCodes: [.unsupportedCapability, .resourceLimitExceeded]
        ),
    ])
}
