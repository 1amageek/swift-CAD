import CADCore
import CADGeometry
import CADTopology

/// Admits the exact smallest body-owned original topology/geometry closure.
struct BRepDrawingBodyClosure {
    func make(_ bodyID: BodyID, in source: BRepModel, maximumEntities: Int,
              tolerance: ModelingTolerance, usage: inout SurfaceSilhouetteUsage) throws -> ValidatedBRepModel {
        guard maximumEntities > 0, let body = source.bodies[bodyID] else {
            throw TopologyError.missingReference("Original drawing body closure is absent or has invalid capacity.")
        }
        var entities = 0
        func retain<Key, Value>(_ key: Key.Type, _ value: Value.Type, usage: inout SurfaceSilhouetteUsage) throws {
            guard entities < maximumEntities else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original drawing body closure entity capacity is exhausted.")
            }
            try usage.preparationStorageCallback(MemoryLayout<(Key,Value)>.stride)
            try usage.consumeWork(); entities += 1
        }
        var model = BRepModel()
        try retain(BodyID.self, Body.self, usage: &usage); model.bodies[bodyID] = body
        for shellID in body.shellIDs {
            try usage.consumeSourceVisit(depth: 0)
            if model.shells[shellID] != nil { continue }
            guard let shell = source.shells[shellID] else { throw TopologyError.missingReference("Drawing closure shell is absent.") }
            try retain(ShellID.self, Shell.self, usage: &usage); model.shells[shellID] = shell
            for faceID in shell.faceIDs {
                try usage.consumeSourceVisit(depth: 0)
                if model.faces[faceID] != nil { continue }
                guard let face = source.faces[faceID], let surface = source.geometry.surfaces[face.surfaceID] else {
                    throw TopologyError.missingReference("Drawing closure face or surface is absent.")
                }
                if model.geometry.surfaces[face.surfaceID] == nil {
                    try retain(SurfaceID.self, Surface3D.self, usage: &usage)
                    model.geometry.surfaces[face.surfaceID] = surface
                }
                try retain(FaceID.self, Face.self, usage: &usage); model.faces[faceID] = face
                for loopID in face.loops {
                    try usage.consumeSourceVisit(depth: 0)
                    if model.loops[loopID] != nil { continue }
                    guard let loop = source.loops[loopID] else { throw TopologyError.missingReference("Drawing closure loop is absent.") }
                    try retain(LoopID.self, Loop.self, usage: &usage); model.loops[loopID] = loop
                    for coedge in loop.coedges {
                        try usage.consumeSourceVisit(depth: 0)
                        if model.edges[coedge.edgeID] != nil { continue }
                        guard let edge = source.edges[coedge.edgeID], let curve = source.geometry.curves[edge.curveID] else {
                            throw TopologyError.missingReference("Drawing closure edge or curve is absent.")
                        }
                        if model.geometry.curves[edge.curveID] == nil {
                            try retain(CurveID.self, Curve3D.self, usage: &usage)
                            model.geometry.curves[edge.curveID] = curve
                        }
                        try retain(EdgeID.self, Edge.self, usage: &usage); model.edges[edge.id] = edge
                        for ordinal in 0..<2 {
                            let vertexID = ordinal == 0 ? edge.startVertexID : edge.endVertexID
                            try usage.consumeSourceVisit(depth: 0)
                            if model.vertices[vertexID] != nil { continue }
                            guard let vertex = source.vertices[vertexID] else { throw TopologyError.missingReference("Drawing closure vertex is absent.") }
                            try retain(VertexID.self, Vertex.self, usage: &usage); model.vertices[vertexID] = vertex
                        }
                    }
                }
            }
        }
        return try ValidatedBRepModel(model, tolerance: tolerance,
            maximumSubdivisionDepth: min(32, usage.maximumDepth), remainingSourceDepth: usage.maximumSourceDepth,
            consumeWork: usage.preparationWorkCallback, consumeStorage: usage.preparationStorageCallback,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
    }
}
