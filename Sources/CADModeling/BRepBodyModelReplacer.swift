import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct BRepBodyModelReplacer {
    package init() {}

    package func replacing(
        bodyID: BodyID,
        with replacementBodyID: BodyID,
        from replacement: BRepModel,
        in model: BRepModel,
        using execution: inout OriginalQueryExecution
    ) throws -> BRepModel {
        try execution.consumeWork(1)
        guard let sourceBody = model.bodies[bodyID],
              var replacementBody = replacement.bodies[replacementBodyID] else {
            throw TopologyError.missingReference("B-rep body replacement is missing body metadata.")
        }
        replacementBody.name = sourceBody.name
        replacementBody.material = sourceBody.material
        var metadataPreservingReplacement = replacement
        try execution.retainStorage(bytes: MemoryLayout<(BodyID, Body)>.stride)
        metadataPreservingReplacement.bodies[replacementBodyID] = replacementBody
        try execution.retainStorage(bytes: MemoryLayout<BodyID>.stride)
        return try replacing(
            bodyIDs: [bodyID],
            with: metadataPreservingReplacement,
            in: model, using: &execution
        )
    }

    package func replacing(
        bodyIDs: Set<BodyID>,
        with replacement: BRepModel,
        in model: BRepModel,
        using execution: inout OriginalQueryExecution
    ) throws -> BRepModel {
        try execution.consumeWork(1)
        guard bodyIDs.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: nil,
                message: "B-rep body replacement requires at least one source body."
            )
        }
        for bodyID in bodyIDs {
            try execution.consumeWork(1)
            guard model.bodies[bodyID] != nil else {
                throw TopologyError.missingReference("B-rep body replacement is missing a source body.")
            }
        }
        var retainedBodyIDs: Set<BodyID> = []
        for bodyID in model.bodies.keys {
            try execution.consumeWork(1)
            if bodyIDs.contains(bodyID) == false {
                try execution.retainStorage(bytes: MemoryLayout<BodyID>.stride)
                retainedBodyIDs.insert(bodyID)
            }
        }
        let retained = try BRepBodySubmodelExtractor().extract(bodyIDs: retainedBodyIDs, from: model, using: &execution)
        try execution.retainStorage(count: 2, stride: MemoryLayout<BRepModel>.stride)
        return try BRepModelCombiner().combined([retained, replacement], using: &execution)
    }

    package func replacing(
        bodyID: BodyID, with replacementBodyID: BodyID, from replacement: BRepModel, in model: BRepModel
    ) throws -> BRepModel {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try replacing(bodyID: bodyID, with: replacementBodyID, from: replacement, in: model, using: &execution)
    }

    package func replacing(bodyIDs: Set<BodyID>, with replacement: BRepModel, in model: BRepModel) throws -> BRepModel {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try replacing(bodyIDs: bodyIDs, with: replacement, in: model, using: &execution)
    }
}
