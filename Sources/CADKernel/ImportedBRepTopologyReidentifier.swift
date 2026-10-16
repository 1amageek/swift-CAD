import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Re-identifies an imported source model before it enters a document snapshot.
///
/// Exchange IDs are source-local and may be repeated when one file is imported
/// more than once. Evaluation IDs are document-owned, so every topology table
/// and every internal reference is copied into the deterministic namespace of
/// the importing feature. The source value itself is never mutated.
package struct ImportedBRepTopologyReidentifier: Sendable {
    package init() {}

    package func reidentify(
        _ source: BRepModel,
        featureID: FeatureID
    ) throws -> ImportedBRepTopologyReidentification {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try reidentify(source, featureID: featureID, using: &execution)
    }

    package func reidentify(_ source: BRepModel, featureID: FeatureID,
        using execution: inout OriginalQueryExecution) throws -> ImportedBRepTopologyReidentification {
        try execution.checkpoint()
        var allocator = FeatureTopologyIDAllocator(featureID: featureID)
        var bodyIDs: [BodyID: BodyID] = [:]
        for sourceID in source.bodies.keys.sorted() {
            try execution.consumeWork(1)
            bodyIDs[sourceID] = allocator.nextBodyID()
        }
        var shellIDs: [ShellID: ShellID] = [:]
        for sourceID in source.shells.keys.sorted() {
            try execution.consumeWork(1)
            shellIDs[sourceID] = allocator.nextShellID()
        }
        var faceIDs: [FaceID: FaceID] = [:]
        for sourceID in source.faces.keys.sorted() {
            try execution.consumeWork(1)
            faceIDs[sourceID] = allocator.nextFaceID()
        }
        var loopIDs: [LoopID: LoopID] = [:]
        for sourceID in source.loops.keys.sorted() {
            try execution.consumeWork(1)
            loopIDs[sourceID] = allocator.nextLoopID()
        }
        var edgeIDs: [EdgeID: EdgeID] = [:]
        for sourceID in source.edges.keys.sorted() {
            try execution.consumeWork(1)
            edgeIDs[sourceID] = allocator.nextEdgeID()
        }
        var vertexIDs: [VertexID: VertexID] = [:]
        for sourceID in source.vertices.keys.sorted() {
            try execution.consumeWork(1)
            vertexIDs[sourceID] = allocator.nextVertexID()
        }
        var curveIDs: [CurveID: CurveID] = [:]
        for sourceID in source.geometry.curves.keys.sorted() {
            try execution.consumeWork(1)
            curveIDs[sourceID] = allocator.nextCurveID()
        }
        var surfaceIDs: [SurfaceID: SurfaceID] = [:]
        for sourceID in source.geometry.surfaces.keys.sorted() {
            try execution.consumeWork(1)
            surfaceIDs[sourceID] = allocator.nextSurfaceID()
        }

        var geometry = GeometryStore()
        for sourceID in source.geometry.curves.keys.sorted() {
            try execution.consumeWork(1)
            guard let curve = source.geometry.curves[sourceID],
                  let targetID = curveIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep curve \(sourceID) could not be re-identified."
                )
            }
            geometry.curves[targetID] = curve
        }
        for sourceID in source.geometry.surfaces.keys.sorted() {
            try execution.consumeWork(1)
            guard let surface = source.geometry.surfaces[sourceID],
                  let targetID = surfaceIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep surface \(sourceID) could not be re-identified."
                )
            }
            geometry.surfaces[targetID] = surface
        }

        var vertices: [VertexID: Vertex] = [:]
        for sourceID in source.vertices.keys.sorted() {
            try execution.consumeWork(1)
            guard let vertex = source.vertices[sourceID],
                  let targetID = vertexIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep vertex \(sourceID) could not be re-identified."
                )
            }
            vertices[targetID] = Vertex(id: targetID, point: vertex.point)
        }

        var edges: [EdgeID: Edge] = [:]
        for sourceID in source.edges.keys.sorted() {
            try execution.consumeWork(1)
            guard let edge = source.edges[sourceID],
                  let targetID = edgeIDs[sourceID],
                  let curveID = curveIDs[edge.curveID],
                  let startVertexID = vertexIDs[edge.startVertexID],
                  let endVertexID = vertexIDs[edge.endVertexID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep edge \(sourceID) has an unresolvable reference."
                )
            }
            edges[targetID] = Edge(
                id: targetID,
                curveID: curveID,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                trim: edge.trim
            )
        }

        var loops: [LoopID: Loop] = [:]
        for sourceID in source.loops.keys.sorted() {
            try execution.consumeWork(1)
            guard let loop = source.loops[sourceID],
                  let targetID = loopIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep loop \(sourceID) could not be re-identified."
                )
            }
            loops[targetID] = Loop(
                id: targetID,
                role: loop.role,
                coedges: try loop.coedges.map { coedge in
                    try execution.consumeWork(1)
                    guard let edgeID = edgeIDs[coedge.edgeID] else {
                        throw TopologyError.missingReference(
                            "Imported B-rep coedge \(coedge.edgeID) references missing edge."
                        )
                    }
                    return Coedge(
                        edgeID: edgeID,
                        orientation: coedge.orientation,
                        surfaceParameterCurve: coedge.surfaceParameterCurve
                    )
                }
            )
        }

        var faces: [FaceID: Face] = [:]
        for sourceID in source.faces.keys.sorted() {
            try execution.consumeWork(1)
            guard let face = source.faces[sourceID],
                  let targetID = faceIDs[sourceID],
                  let surfaceID = surfaceIDs[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep face \(sourceID) has an unresolvable surface."
                )
            }
            faces[targetID] = Face(
                id: targetID,
                surfaceID: surfaceID,
                loops: try face.loops.map { loopID in
                    try execution.consumeWork(1)
                    guard let targetLoopID = loopIDs[loopID] else {
                        throw TopologyError.missingReference(
                            "Imported B-rep face \(sourceID) references missing loop \(loopID)."
                        )
                    }
                    return targetLoopID
                },
                orientation: face.orientation
            )
        }

        var shells: [ShellID: Shell] = [:]
        for sourceID in source.shells.keys.sorted() {
            try execution.consumeWork(1)
            guard let shell = source.shells[sourceID],
                  let targetID = shellIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep shell \(sourceID) could not be re-identified."
                )
            }
            shells[targetID] = Shell(
                id: targetID,
                faceIDs: try shell.faceIDs.map { faceID in
                    try execution.consumeWork(1)
                    guard let targetFaceID = faceIDs[faceID] else {
                        throw TopologyError.missingReference(
                            "Imported B-rep shell \(sourceID) references missing face \(faceID)."
                        )
                    }
                    return targetFaceID
                },
                orientation: shell.orientation
            )
        }

        var bodies: [BodyID: Body] = [:]
        for sourceID in source.bodies.keys.sorted() {
            try execution.consumeWork(1)
            guard let body = source.bodies[sourceID],
                  let targetID = bodyIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep body \(sourceID) could not be re-identified."
                )
            }
            let topology: BodyTopology
            switch body.topology {
            case let .solid(components):
                topology = .solid(components: try components.map { component in
                    try execution.consumeWork(1)
                    guard let outerShellID = shellIDs[component.outerShellID] else {
                        throw TopologyError.missingReference(
                            "Imported B-rep body \(sourceID) references missing outer shell \(component.outerShellID)."
                        )
                    }
                    return SolidShellComponent(
                        outerShellID: outerShellID,
                        voidShellIDs: try component.voidShellIDs.map { shellID in
                            try execution.consumeWork(1)
                            guard let targetShellID = shellIDs[shellID] else {
                                throw TopologyError.missingReference(
                                    "Imported B-rep body \(sourceID) references missing void shell \(shellID)."
                                )
                            }
                            return targetShellID
                        }
                    )
                })
            case let .sheet(sourceShellIDs):
                topology = .sheet(shellIDs: try sourceShellIDs.map { shellID in
                    try execution.consumeWork(1)
                    guard let targetShellID = shellIDs[shellID] else {
                        throw TopologyError.missingReference(
                            "Imported B-rep body \(sourceID) references missing sheet shell \(shellID)."
                        )
                    }
                    return targetShellID
                })
            }
            bodies[targetID] = Body(
                id: targetID,
                topology: topology,
                name: body.name,
                material: body.material
            )
        }

        try execution.checkpoint()
        return ImportedBRepTopologyReidentification(
            model: BRepModel(
                geometry: geometry,
                bodies: bodies,
                shells: shells,
                faces: faces,
                loops: loops,
                edges: edges,
                vertices: vertices
            ),
            bodyIDs: bodyIDs,
            faceIDs: faceIDs,
            edgeIDs: edgeIDs,
            vertexIDs: vertexIDs
        )
    }
}

package struct ImportedBRepTopologyReidentification: Sendable {
    package let model: BRepModel
    package let bodyIDs: [BodyID: BodyID]
    package let faceIDs: [FaceID: FaceID]
    package let edgeIDs: [EdgeID: EdgeID]
    package let vertexIDs: [VertexID: VertexID]

    package init(
        model: BRepModel,
        bodyIDs: [BodyID: BodyID],
        faceIDs: [FaceID: FaceID],
        edgeIDs: [EdgeID: EdgeID],
        vertexIDs: [VertexID: VertexID]
    ) {
        self.model = model
        self.bodyIDs = bodyIDs
        self.faceIDs = faceIDs
        self.edgeIDs = edgeIDs
        self.vertexIDs = vertexIDs
    }
}
