import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct BodyTopologyScope: Sendable {
    package let references: Set<TopologyReference>

    package init(bodyID: BodyID, model: BRepModel) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(bodyID: bodyID, model: model, using: &execution)
    }

    package init(bodyID: BodyID, model: BRepModel, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Body topology scope is missing its body.")
        }
        try execution.retainStorage(bytes: MemoryLayout<TopologyReference>.stride)
        var collected: Set<TopologyReference> = [.body(bodyID)]
        for shellID in try body.originalShellIDs(using: &execution) {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Body topology scope is missing a shell.")
            }
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                try Self.insert(.face(faceID), into: &collected, using: &execution)
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Body topology scope is missing a face.")
                }
                for loopID in face.loops {
                    try execution.consumeWork(1)
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Body topology scope is missing a loop.")
                    }
                    for coedge in loop.coedges {
                        try execution.consumeWork(1)
                        try Self.insert(.edge(coedge.edgeID), into: &collected, using: &execution)
                        guard let edge = model.edges[coedge.edgeID] else {
                            throw TopologyError.missingReference("Body topology scope is missing an edge.")
                        }
                        try Self.insert(.vertex(edge.startVertexID), into: &collected, using: &execution)
                        try Self.insert(.vertex(edge.endVertexID), into: &collected, using: &execution)
                    }
                }
            }
        }
        references = collected
    }

    package func subshapeIDs(in index: SubshapeIndex) throws -> Set<SubshapeID> {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try subshapeIDs(in: index, using: &execution)
    }

    package func subshapeIDs(in index: SubshapeIndex, using execution: inout OriginalQueryExecution) throws -> Set<SubshapeID> {
        try execution.consumeWork(1)
        var result: Set<SubshapeID> = []
        for (subshapeID, reference) in index.entries {
            try execution.consumeWork(1)
            if references.contains(reference), result.contains(subshapeID) == false {
                try execution.retainStorage(bytes: MemoryLayout<SubshapeID>.stride)
                result.insert(subshapeID)
            }
        }
        return result
    }

    private static func insert(
        _ reference: TopologyReference, into references: inout Set<TopologyReference>,
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        if references.contains(reference) == false {
            try execution.retainStorage(bytes: MemoryLayout<TopologyReference>.stride)
            references.insert(reference)
        }
    }
}
