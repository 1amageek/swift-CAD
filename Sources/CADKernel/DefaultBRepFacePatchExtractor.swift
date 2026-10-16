import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct DefaultBRepFacePatchExtractor: BRepFacePatchExtracting {
    public init() {}

    public func extract(bodyID: BodyID, featureID: FeatureID, from model: BRepModel,
        tolerance: ModelingTolerance) throws -> BRepSewingExtraction {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try extract(bodyID: bodyID, featureID: featureID, from: model,
            sourceSubshapes: [:], tolerance: tolerance, using: &execution)
    }

    public func extract(bodyID: BodyID, featureID: FeatureID, from model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepSewingExtraction {
        try extract(bodyID: bodyID, featureID: featureID, from: model,
            sourceSubshapes: [:], tolerance: tolerance, using: &execution)
    }

    public func extract(bodyID: BodyID, featureID: FeatureID, from model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference], tolerance: ModelingTolerance) throws -> BRepSewingExtraction {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try extract(bodyID: bodyID, featureID: featureID, from: model,
            sourceSubshapes: sourceSubshapes, tolerance: tolerance, using: &execution)
    }

    public func extract(bodyID: BodyID, featureID: FeatureID, from model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference], tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BRepSewingExtraction {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                tolerance: tolerance,
                message: "Face-patch extraction references a missing body."
            )
        }
        var sourceStableKeys: [TopologyReference: BRepSewingStableKey] = [:]
        try OriginalParameterQueryStorage.set(.body, for: .body(bodyID), in: &sourceStableKeys, using: &execution)
        var sewingShells: [BRepSewingShell] = []
        var stableIDByShellID: [ShellID: String] = [:]
        for (shellIndex, shellID) in body.shellIDs.enumerated() {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw missingReference("Face-patch extraction references a missing shell.", tolerance: tolerance)
            }
            let shellBytes = 6 + digits(shellIndex)
            try execution.consumeWork(shellBytes)
            try execution.retainStorage(bytes: shellBytes)
            let shellStableID = "shell:\(shellIndex)"
            try OriginalParameterQueryStorage.set(shellStableID, for: shellID, in: &stableIDByShellID, using: &execution)
            var patches: [BRepSewingFacePatch] = []
            for (faceIndex, faceID) in shell.faceIDs.enumerated() {
                try execution.consumeWork(1)
                let faceBytes = shellBytes + 6 + digits(faceIndex)
                try execution.consumeWork(faceBytes)
                try execution.retainStorage(bytes: faceBytes)
                let faceStableID = "\(shellStableID):face:\(faceIndex)"
                let result = try SourceBRepFacePatchBuilder().build(
                    faceID: faceID,
                    stableID: faceStableID,
                    from: model,
                    sourceSubshapes: sourceSubshapes,
                    tolerance: tolerance, using: &execution
                )
                for (reference, stableKey) in result.stableKeys {
                    try execution.consumeWork(1)
                    if sourceStableKeys[reference] == nil {
                        try OriginalParameterQueryStorage.set(stableKey, for: reference, in: &sourceStableKeys, using: &execution)
                    }
                }
                try OriginalParameterQueryStorage.append(result.patch, to: &patches, using: &execution)
            }
            try OriginalParameterQueryStorage.append(BRepSewingShell(
                stableID: shellStableID,
                patches: patches,
                orientation: shell.orientation
            ), to: &sewingShells, using: &execution)
        }
        let sewingBodyTopology: BRepSewingBodyTopology
        switch body.topology {
        case .sheet(let shellIDs):
            sewingBodyTopology = .sheet(shellStableIDs: try OriginalParameterQueryStorage.map(shellIDs, using: &execution) { shellID, execution in
                guard let stableID = stableIDByShellID[shellID] else {
                    throw missingReference(
                        "Face-patch extraction lost a sheet shell identity.",
                        tolerance: tolerance
                    )
                }
                return stableID
            })
        case .solid(let components):
            sewingBodyTopology = .solid(components: try OriginalParameterQueryStorage.map(components, using: &execution) { component, execution in
                guard let outerStableID = stableIDByShellID[component.outerShellID] else {
                    throw missingReference(
                        "Face-patch extraction lost a solid outer shell identity.",
                        tolerance: tolerance
                    )
                }
                let voidStableIDs = try OriginalParameterQueryStorage.map(component.voidShellIDs, using: &execution) { shellID, execution in
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
        let request = try BRepSewingRequest(
            featureID: featureID,
            bodyTopology: sewingBodyTopology,
            shells: sewingShells, using: &execution
        )
        try request.validate(tolerance: tolerance, using: &execution)
        return BRepSewingExtraction(request: request, sourceStableKeys: sourceStableKeys)
    }

    private func digits(_ number: Int) -> Int {
        var n = number, count = 1
        while n >= 10 { n /= 10; count += 1 }
        return count
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
