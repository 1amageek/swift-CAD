import CADCore
import CADIR

public struct DocumentCacheMaterializer: Sendable {
    public init() {}

    public func materializedDocument(
        from evaluatedDocument: EvaluatedDocument
    ) throws -> EvaluatedDocument {
        try CurrentTaskCancellationChecker().checkCancellation()
        return try evaluatedDocument.replacingCaches(caches(for: evaluatedDocument))
    }

    public func caches(for evaluatedDocument: EvaluatedDocument) throws -> DocumentCaches {
        let document = evaluatedDocument.document
        let configuration = evaluatedDocument.configuration
        let sourceFingerprint = try document.sourceFingerprint(
            tolerance: configuration.tolerance
        )
        let brepCache = BRepCache(
            designRevision: document.designGraph.revision,
            parameterRevision: document.parameters.revision,
            sourceFingerprint: sourceFingerprint,
            kernelVersion: .current,
            tolerance: configuration.tolerance,
            model: evaluatedDocument.brep,
            subshapes: evaluatedDocument.subshapes
        )
        var meshCaches: [BodyID: MeshCache] = [:]
        meshCaches.reserveCapacity(evaluatedDocument.meshes.count)
        for (bodyID, mesh) in evaluatedDocument.meshes {
            try CurrentTaskCancellationChecker().checkCancellation()
            meshCaches[bodyID] = try MeshCache(
                        bodyID: bodyID,
                        designRevision: document.designGraph.revision,
                        parameterRevision: document.parameters.revision,
                        sourceFingerprint: sourceFingerprint,
                        kernelVersion: .current,
                        tolerance: configuration.tolerance,
                        tessellationOptions: configuration.tessellationOptions,
                        purpose: configuration.meshArtifactPurpose,
                        mesh: mesh
                    )
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return DocumentCaches(brep: brepCache, meshes: meshCaches)
    }
}
