import CADIR

public struct DocumentCacheMaterializer: Sendable {
    public init() {}

    public func materializedDocument(
        from evaluatedDocument: EvaluatedDocument
    ) throws -> EvaluatedDocument {
        EvaluatedDocument(
            document: evaluatedDocument.document,
            parameters: evaluatedDocument.parameters,
            brep: evaluatedDocument.brep,
            meshes: evaluatedDocument.meshes,
            curves: evaluatedDocument.curves,
            caches: try caches(for: evaluatedDocument),
            generatedNames: evaluatedDocument.generatedNames,
            configuration: evaluatedDocument.configuration,
            evaluationMetrics: evaluatedDocument.evaluationMetrics
        )
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
            persistentNames: PersistentNameMap(
                evaluatedDocument.generatedNames.materializedDictionary()
            )
        )
        let meshCaches = Dictionary(
            uniqueKeysWithValues: evaluatedDocument.meshes.map { bodyID, mesh in
                (
                    bodyID,
                    MeshCache(
                        bodyID: bodyID,
                        designRevision: document.designGraph.revision,
                        parameterRevision: document.parameters.revision,
                        sourceFingerprint: sourceFingerprint,
                        kernelVersion: .current,
                        tolerance: configuration.tolerance,
                        tessellationOptions: configuration.tessellationOptions,
                        mesh: mesh
                    )
                )
            }
        )
        return DocumentCaches(brep: brepCache, meshes: meshCaches)
    }
}
