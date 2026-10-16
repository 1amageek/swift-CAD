import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Takes an operand body out of a model that a feature consumes, and names the subshapes that
/// referred to it.
struct BRepBodyTopologyRemoval {
    /// The subshapes naming any topology of `bodyID`.
    func subshapeIDs(
        bodyID: BodyID,
        in model: BRepModel,
        subshapes: [SubshapeID: TopologyReference]
    ) throws -> Set<SubshapeID> {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try subshapeIDs(bodyID: bodyID, in: model, subshapes: subshapes,
            using: &execution)
    }

    func subshapeIDs(bodyID: BodyID, in model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        using execution: inout OriginalQueryExecution) throws -> Set<SubshapeID> {
        let references = try topologyReferences(for: bodyID, in: model, using: &execution)
        var result: Set<SubshapeID> = []
        for (subshapeID, reference) in subshapes {
            try execution.consumeWork(1)
            try execution.consumeWork(1)
            if references.contains(reference) {
                try OriginalParameterQueryStorage.insert(subshapeID, in: &result, using: &execution)
            }
        }
        return result
    }

    private func topologyReferences(for bodyID: BodyID, in model: BRepModel,
        using execution: inout OriginalQueryExecution) throws -> Set<TopologyReference> {
        try execution.consumeWork(1)
        guard let body = model.bodies[bodyID] else {
            return []
        }
        var references: Set<TopologyReference> = []
        try OriginalParameterQueryStorage.insert(.body(bodyID), in: &references, using: &execution)
        for shellID in body.shellIDs {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                continue
            }
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.insert(.face(faceID), in: &references, using: &execution)
                guard let face = model.faces[faceID] else {
                    continue
                }
                for loopID in face.loops {
                    try execution.consumeWork(1)
                    guard let loop = model.loops[loopID] else {
                        continue
                    }
                    for orientedEdge in loop.edges {
                        try execution.consumeWork(1)
                        try OriginalParameterQueryStorage.insert(.edge(orientedEdge.edgeID), in: &references, using: &execution)
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            continue
                        }
                        try OriginalParameterQueryStorage.insert(.vertex(edge.startVertexID), in: &references, using: &execution)
                        try OriginalParameterQueryStorage.insert(.vertex(edge.endVertexID), in: &references, using: &execution)
                    }
                }
            }
        }
        return references
    }

    /// Removes `bodyID` with its shells, faces, loops, edges, vertices, and geometry.
    func remove(bodyID: BodyID, from model: inout BRepModel) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try remove(bodyID: bodyID, from: &model, using: &execution)
    }

    func remove(bodyID: BodyID, from model: inout BRepModel,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let body = model.bodies.removeValue(forKey: bodyID) else {
            throw TopologyError.missingReference("Missing boolean body \(bodyID).")
        }
        var surfaceIDs = Set<SurfaceID>()
        var curveIDs = Set<CurveID>()
        var loopIDs = Set<LoopID>()
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()

        for shellID in body.shellIDs {

            try execution.consumeWork(1)
            guard let shell = model.shells.removeValue(forKey: shellID) else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                guard let face = model.faces.removeValue(forKey: faceID) else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                try OriginalParameterQueryStorage.insert(face.surfaceID, in: &surfaceIDs, using: &execution)
                for loopID in face.loops {
                    try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.insert(loopID, in: &loopIDs, using: &execution)
                }
            }
        }
        for loopID in loopIDs {
            try execution.consumeWork(1)
            guard let loop = model.loops.removeValue(forKey: loopID) else {
                throw TopologyError.missingReference("Missing boolean loop \(loopID).")
            }
            for orientedEdge in loop.edges {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.insert(orientedEdge.edgeID, in: &edgeIDs, using: &execution)
            }
        }
        for edgeID in edgeIDs {
            try execution.consumeWork(1)
            guard let edge = model.edges.removeValue(forKey: edgeID) else {
                throw TopologyError.missingReference("Missing boolean edge \(edgeID).")
            }
            try OriginalParameterQueryStorage.insert(edge.curveID, in: &curveIDs, using: &execution)
            try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &vertexIDs, using: &execution)
            try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &vertexIDs, using: &execution)
        }
        for vertexID in vertexIDs {
            try execution.consumeWork(1)
            model.vertices.removeValue(forKey: vertexID)
        }
        for curveID in curveIDs {
            try execution.consumeWork(1)
            model.geometry.curves.removeValue(forKey: curveID)
        }
        for surfaceID in surfaceIDs {
            try execution.consumeWork(1)
            model.geometry.surfaces.removeValue(forKey: surfaceID)
        }
    }
}
