import CADCore
import CADIR
import CADModeling
import CADTopology

/// What chosen faces of a body make when extracted, for callers that must declare the output
/// before appending (Alternative Duplicate).
public struct ExtractFaceClosure {
    public init() {}

    /// Whether the faces close: every face of each shell they lie on, on a solid.
    public func closes(
        faces: [StableSubshapeReference],
        source featureID: FeatureID,
        in document: EvaluatedDocument
    ) throws -> Bool {
        let (body, faceSet) = try resolve(faces, source: featureID, in: document)
        return faceSet.closes(body: body, model: document.brep)
    }

    /// Whether the faces make a solid (`ExtractSelection.solidFaces`) rather than only a sheet:
    /// they close, or they bound one with the faces around them (`ExtractFacePlugBuilder`). Faces
    /// the plug refuses — they bound nothing, or the faces around cannot grow over them — make
    /// only a sheet; any other failure is thrown.
    public func makesSolid(
        faces: [StableSubshapeReference],
        source featureID: FeatureID,
        in document: EvaluatedDocument
    ) throws -> Bool {
        let (body, faceSet) = try resolve(faces, source: featureID, in: document)
        guard body.kind == .solid else { return false }
        if faceSet.closes(body: body, model: document.brep) { return true }
        let tolerance = document.configuration.tolerance
        let faceIDs = Set(try faceSet.facesByShell.flatMap { entry -> [FaceID] in
            guard let shell = document.brep.shells[entry.shellID] else {
                throw TopologyError.missingReference("A chosen face's shell is missing.")
            }
            return entry.faceIndices.map { shell.faceIDs[$0] }
        })
        guard case let .body(bodyID) = document.subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)] else {
            throw TopologyError.missingReference("The faces' source has no evaluated body.")
        }
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(), brep: document.brep, profiles: [:],
            subshapes: document.subshapes, lineage: document.lineage, tolerance: tolerance
        )
        do {
            _ = try ExtractFacePlugBuilder(tolerance: tolerance).plug(faces: faceIDs, of: bodyID, featureID: FeatureID(), context: context)
            return true
        } catch let refusal as KernelError where refusal.code == .invalidInput || refusal.code == .topologyFailure {
            return false
        }
    }

    private func resolve(
        _ faces: [StableSubshapeReference],
        source featureID: FeatureID,
        in document: EvaluatedDocument
    ) throws -> (Body, ExtractFaceSet) {
        let tolerance = document.configuration.tolerance
        guard case let .body(bodyID) = document.subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)],
              let body = document.brep.bodies[bodyID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID, tolerance: tolerance,
                message: "The faces' source has no evaluated body.")
        }
        let faceSet = try ExtractFaceSet(
            references: faces, body: body, model: document.brep, subshapes: document.subshapes,
            lineage: document.lineage, resolver: StableSubshapeResolver(), tolerance: tolerance
        )
        return (body, faceSet)
    }
}
