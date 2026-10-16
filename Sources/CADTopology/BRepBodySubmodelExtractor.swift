import HashTreeCollections
import CADCore
import CADGeometry

/// Extracts the ownership-closed topology and geometry for a set of bodies.
///
/// Body submodel extraction is a topology operation. Keeping it in CADTopology
/// lets validation certificates and higher-level modeling features share the
/// same ownership traversal without reversing the package dependency graph.
package struct BRepBodySubmodelExtractor {
    package init() {}

    package func extract(bodyIDs: Set<BodyID>, from model: BRepModel) throws -> BRepModel {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try extract(bodyIDs: bodyIDs, from: model, using: &execution)
    }

    package func extract(
        bodyIDs: Set<BodyID>,
        from model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> BRepModel {
        try execution.checkpoint(); try execution.consumeWork(1)
        var result = BRepModel()

        for bodyID in bodyIDs {
            try execution.checkpoint(); try execution.consumeWork(1)
            guard let body = model.bodies[bodyID] else {
                throw TopologyError.missingReference("Missing body \(bodyID).")
            }
            if result.bodies[bodyID] == nil {
                try execution.retainStorage(bytes: MemoryLayout<(BodyID, Body)>.stride)
                result.bodies[bodyID] = body
            }
            for shellID in try body.originalShellIDs(using: &execution) {
                try execution.checkpoint(); try execution.consumeWork(1)
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                if result.shells[shellID] == nil {
                    try execution.retainStorage(bytes: MemoryLayout<(ShellID, Shell)>.stride)
                    result.shells[shellID] = shell
                }
                for faceID in shell.faceIDs {
                    try execution.checkpoint(); try execution.consumeWork(1)
                    guard let face = model.faces[faceID],
                          let surface = model.geometry.surfaces[face.surfaceID] else {
                        throw TopologyError.missingReference(
                            "Missing face geometry for \(faceID)."
                        )
                    }
                    if result.faces[faceID] == nil {
                        try execution.retainStorage(bytes: MemoryLayout<(FaceID, Face)>.stride)
                        result.faces[faceID] = face
                    }
                    if result.geometry.surfaces[face.surfaceID] == nil {
                        try execution.retainStorage(bytes: MemoryLayout<(SurfaceID, Surface3D)>.stride)
                        result.geometry.surfaces[face.surfaceID] = surface
                    }
                    for loopID in face.loops {
                        try execution.checkpoint(); try execution.consumeWork(1)
                        guard let loop = model.loops[loopID] else {
                            throw TopologyError.missingReference("Missing loop \(loopID).")
                        }
                        if result.loops[loopID] == nil {
                            try execution.retainStorage(bytes: MemoryLayout<(LoopID, Loop)>.stride)
                            result.loops[loopID] = loop
                        }
                        for orientedEdge in loop.coedges {
                            try execution.checkpoint(); try execution.consumeWork(1)
                            let edgeID = orientedEdge.edgeID
                            guard let edge = model.edges[edgeID],
                                  let curve = model.geometry.curves[edge.curveID],
                                  let startVertex = model.vertices[edge.startVertexID],
                                  let endVertex = model.vertices[edge.endVertexID] else {
                                throw TopologyError.missingReference(
                                    "Missing edge geometry for \(edgeID)."
                                )
                            }
                            if result.edges[edgeID] == nil {
                                try execution.retainStorage(bytes: MemoryLayout<(EdgeID, Edge)>.stride)
                                result.edges[edgeID] = edge
                            }
                            if result.geometry.curves[edge.curveID] == nil {
                                try execution.retainStorage(bytes: MemoryLayout<(CurveID, Curve3D)>.stride)
                                result.geometry.curves[edge.curveID] = curve
                            }
                            if result.vertices[edge.startVertexID] == nil {
                                try execution.retainStorage(bytes: MemoryLayout<(VertexID, Vertex)>.stride)
                                result.vertices[edge.startVertexID] = startVertex
                            }
                            if result.vertices[edge.endVertexID] == nil {
                                try execution.retainStorage(bytes: MemoryLayout<(VertexID, Vertex)>.stride)
                                result.vertices[edge.endVertexID] = endVertex
                            }
                        }
                    }
                }
            }
        }
        return result
    }
}
