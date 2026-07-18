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
        for (shellIndex, shellID) in body.shellIDs.enumerated() {
            guard let shell = model.shells[shellID] else {
                throw missingReference("Face-patch extraction references a missing shell.", tolerance: tolerance)
            }
            let shellStableID = "shell:\(shellIndex)"
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
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: body.kind,
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
