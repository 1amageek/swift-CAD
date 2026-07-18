import CADCore
import CADIR
import CADTopology

package struct BRepBodyModelReplacer {
    package init() {}

    package func replacing(
        bodyID: BodyID,
        with replacementBodyID: BodyID,
        from replacement: BRepModel,
        in model: BRepModel
    ) throws -> BRepModel {
        guard let sourceBody = model.bodies[bodyID],
              var replacementBody = replacement.bodies[replacementBodyID] else {
            throw TopologyError.missingReference("B-rep body replacement is missing body metadata.")
        }
        replacementBody.name = sourceBody.name
        replacementBody.material = sourceBody.material
        var metadataPreservingReplacement = replacement
        metadataPreservingReplacement.bodies[replacementBodyID] = replacementBody
        return try replacing(
            bodyIDs: [bodyID],
            with: metadataPreservingReplacement,
            in: model
        )
    }

    package func replacing(
        bodyIDs: Set<BodyID>,
        with replacement: BRepModel,
        in model: BRepModel
    ) throws -> BRepModel {
        guard bodyIDs.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: nil,
                message: "B-rep body replacement requires at least one source body."
            )
        }
        let missingBodyIDs = bodyIDs.subtracting(model.bodies.keys)
        guard missingBodyIDs.isEmpty else {
            throw TopologyError.missingReference("B-rep body replacement is missing a source body.")
        }
        let retainedBodyIDs = Set(model.bodies.keys).subtracting(bodyIDs)
        let retained = try BRepBodySubmodelExtractor().extract(bodyIDs: retainedBodyIDs, from: model)
        return try BRepModelCombiner().combined([retained, replacement])
    }
}
