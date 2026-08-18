import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct DefaultBRepFacePatchExtractor: BRepFacePatchExtracting {
    public init() {}

    public func extract(
        bodyID: BodyID,
        featureID: FeatureID,
        from model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingExtraction {
        try extract(
            bodyID: bodyID,
            featureID: featureID,
            from: model,
            sourceSubshapes: [:],
            tolerance: tolerance
        )
    }

    public func extract(
        bodyID: BodyID,
        featureID: FeatureID,
        from model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingExtraction {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Face-patch extraction references a missing body."
            )
        }
        var sourceStableKeys: [TopologyReference: BRepSewingStableKey] = [.body(bodyID): .body]
        var sewingShells: [BRepSewingShell] = []
        var stableIDByShellID: [ShellID: String] = [:]
        for (shellIndex, shellID) in body.shellIDs.enumerated() {
            guard let shell = model.shells[shellID] else {
                throw missingReference("Face-patch extraction references a missing shell.", tolerance: tolerance)
            }
            let shellStableID = "shell:\(shellIndex)"
            stableIDByShellID[shellID] = shellStableID
            var patches: [BRepSewingFacePatch] = []
            for (faceIndex, faceID) in shell.faceIDs.enumerated() {
                let faceStableID = "\(shellStableID):face:\(faceIndex)"
                let result = try SourceBRepFacePatchBuilder().build(
                    faceID: faceID,
                    stableID: faceStableID,
                    from: model,
                    sourceSubshapes: sourceSubshapes,
                    tolerance: tolerance
                )
                for (reference, stableKey) in result.stableKeys where sourceStableKeys[reference] == nil {
                    sourceStableKeys[reference] = stableKey
                }
                patches.append(result.patch)
            }
            sewingShells.append(BRepSewingShell(
                stableID: shellStableID,
                patches: patches,
                orientation: shell.orientation
            ))
        }
        let sewingBodyTopology: BRepSewingBodyTopology
        switch body.topology {
        case .sheet(let shellIDs):
            sewingBodyTopology = .sheet(shellStableIDs: try shellIDs.map { shellID in
                guard let stableID = stableIDByShellID[shellID] else {
                    throw missingReference(
                        "Face-patch extraction lost a sheet shell identity.",
                        tolerance: tolerance
                    )
                }
                return stableID
            })
        case .solid(let components):
            sewingBodyTopology = .solid(components: try components.map { component in
                guard let outerStableID = stableIDByShellID[component.outerShellID] else {
                    throw missingReference(
                        "Face-patch extraction lost a solid outer shell identity.",
                        tolerance: tolerance
                    )
                }
                let voidStableIDs = try component.voidShellIDs.map { shellID in
                    guard let stableID = stableIDByShellID[shellID] else {
                        throw missingReference(
                            "Face-patch extraction lost a solid void shell identity.",
                            tolerance: tolerance
                        )
                    }
                    return stableID
                }
                return BRepSewingSolidComponent(
                    outerShellStableID: outerStableID,
                    voidShellStableIDs: voidStableIDs
                )
            })
        }
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyTopology: sewingBodyTopology,
            shells: sewingShells
        )
        try request.validate(tolerance: tolerance)
        return BRepSewingExtraction(request: request, sourceStableKeys: sourceStableKeys)
    }

    private func missingReference(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }
}
