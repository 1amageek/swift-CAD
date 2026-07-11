import CADCore
import CADIR

public extension EvaluatedDocument {
    func validate(kernelVersion expectedKernelVersion: SchemaVersion = .current) throws {
        guard let brepCache = caches.brep else {
            throw CacheValidationError.missingBRepCache
        }
        let tolerance = brepCache.tolerance
        try document.validate(tolerance: tolerance)
        try validateResolvedParametersMatchSource()

        let tessellationOptions = firstMeshCache()?.tessellationOptions ?? .standard

        try caches.validateFreshness(
            for: document,
            tolerance: tolerance,
            tessellationOptions: tessellationOptions,
            kernelVersion: expectedKernelVersion
        )
        try validateTopLevelBRepMatchesCache(brepCache)
        try brep.validate(tolerance: tolerance)
        try validateTopLevelMeshesMatchBRep(
            tolerance: tolerance,
            tessellationOptions: tessellationOptions
        )
        try validateTopLevelMeshesMatchCaches()
        try validateCurveOutputs(tolerance: tolerance)
        try validateGeneratedNames()
    }

    private func validateResolvedParametersMatchSource() throws {
        let resolvedParameters = try ParameterResolver().resolve(document.parameters)
        guard parameters.values == resolvedParameters.values,
              parameters.names == resolvedParameters.names else {
            throw CacheValidationError.staleBRepCache("Resolved parameters do not match the source document.")
        }
    }

    private func validateTopLevelBRepMatchesCache(_ brepCache: BRepCache) throws {
        guard brep == brepCache.model else {
            throw CacheValidationError.staleBRepCache("Top-level B-rep does not match the B-rep cache.")
        }
        guard generatedNames.materializedDictionary() == brepCache.persistentNames.entries else {
            throw CacheValidationError.staleBRepCache("Generated persistent names do not match the B-rep cache.")
        }
    }

    private func firstMeshCache() -> MeshCache? {
        caches.meshes.sorted { lhs, rhs in
            lhs.key.description < rhs.key.description
        }.first?.value
    }

    private func validateTopLevelMeshesMatchBRep(
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions
    ) throws {
        let expectedMeshes = try MeshTessellator(tolerance: tolerance).tessellate(
            model: brep,
            options: tessellationOptions
        )
        guard !expectedMeshes.isEmpty else {
            guard brep.bodies.isEmpty else {
                throw FeatureEvaluationError.emptyResult("Evaluated B-rep produces no body meshes.")
            }
            try validateBodyIDs(
                actual: Set(meshes.keys),
                expected: [],
                missingReason: "Evaluated document is missing a mesh generated from its B-rep.",
                extraReason: "Evaluated document contains a mesh not generated from its B-rep."
            )
            return
        }
        try validateBodyIDs(
            actual: Set(meshes.keys),
            expected: Set(expectedMeshes.keys),
            missingReason: "Evaluated document is missing a mesh generated from its B-rep.",
            extraReason: "Evaluated document contains a mesh not generated from its B-rep."
        )
        for bodyID in expectedMeshes.keys {
            guard let actualMesh = meshes[bodyID],
                  let expectedMesh = expectedMeshes[bodyID],
                  actualMesh == expectedMesh else {
                throw CacheValidationError.staleMeshCache(
                    bodyID: bodyID,
                    reason: "Evaluated mesh content does not match tessellation of the top-level B-rep."
                )
            }
        }
    }

    private func validateTopLevelMeshesMatchCaches() throws {
        try validateBodyIDs(
            actual: Set(meshes.keys),
            expected: Set(caches.meshes.keys),
            missingReason: "Evaluated document is missing a mesh present in cache metadata.",
            extraReason: "Evaluated document contains a mesh absent from cache metadata."
        )
        for bodyID in meshes.keys {
            guard let meshCache = caches.meshes[bodyID],
                  meshCache.mesh == meshes[bodyID] else {
                throw CacheValidationError.staleMeshCache(
                    bodyID: bodyID,
                    reason: "Top-level evaluated mesh does not match the mesh cache."
                )
            }
        }
    }

    internal func validateGeneratedNames() throws {
        try GeneratedNameValidator.validate(generatedNames, in: brep)
    }

    internal func validateCurveOutputs(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        for (featureID, featureCurves) in curves {
            guard let node = document.designGraph.nodes[featureID],
                  node.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Evaluated curve output references a feature without a curve output.")
            }
            guard !featureCurves.isEmpty else {
                throw FeatureEvaluationError.emptyResult("Evaluated curve output contains no curves.")
            }
            for curve in featureCurves {
                guard curve.sourceFeatureID == featureID else {
                    throw FeatureEvaluationError.invalidGraph("Evaluated curve source feature does not match its output table key.")
                }
                try curve.validate(tolerance: tolerance)
            }
        }
    }

}

private func validateBodyIDs(
    actual: Set<BodyID>,
    expected: Set<BodyID>,
    missingReason: String,
    extraReason: String
) throws {
    if let missingBodyID = expected.subtracting(actual)
        .sorted(by: { $0.description < $1.description })
        .first {
        throw CacheValidationError.staleMeshCache(bodyID: missingBodyID, reason: missingReason)
    }
    if let extraBodyID = actual.subtracting(expected)
        .sorted(by: { $0.description < $1.description })
        .first {
        throw CacheValidationError.staleMeshCache(bodyID: extraBodyID, reason: extraReason)
    }
}
