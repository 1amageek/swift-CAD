import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology

enum OriginalNativeRectangleSmoke {
    static func run() throws {
        for direction in [SurfaceParameterDirection.u, .v] {
            let model = try sheet(surface: surface(direction: direction))
            let original = model
            let requests = [
                TessellationOptions(linearTolerance: 1e-3, angularTolerance: 0.08, maxEdgeLength: 0.25),
                TessellationOptions(linearTolerance: 1e-5, angularTolerance: 0.08, maxEdgeLength: 0.25),
                TessellationOptions(linearTolerance: 1e-3, angularTolerance: 0.005, maxEdgeLength: 0.25),
            ]
            var counts: [Int] = []
            for options in requests {
                let meshes = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
                guard meshes.count == 1, let mesh = meshes.values.first else {
                    throw failure("The original rectangle did not publish exactly one mesh.")
                }
                try verify(mesh, model: model, direction: direction, options: options)
                counts.append(mesh.indices.count)
            }
            try require(counts[1] > counts[0] && counts[2] > counts[0],
                        "Original position and normal requests did not refine the mesh.")
            try require(model == original, "Original rectangle tessellation modified source geometry or topology.")
        }
        print("ORIGINAL_NONCLAMPED_RECTANGLE_OK")

        let model = try sheet(surface: surface(direction: .u))
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 1
        do {
            _ = try MeshTessellator(tolerance: .standard, limits: limits).tessellate(model: model)
            throw failure("The original rectangle ignored its caller's vertex ceiling.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(.vertexCount, requested, limit) = error,
                  requested > 1, limit == 1 else { throw error }
        }
        print("ORIGINAL_NONCLAMPED_STORAGE_REFUSAL_OK")

        // S(u,v)=(u,(u-2.5)*v,0) has nondegenerate boundary edges and zero
        // tangent area inside, so validation reaches original-panel regularity.
        let collapsed = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 1, 2, 3, 4, 5], vKnots: [0, 0, 1, 1], controlPoints: [
                [Point3D(x: 1.5, y: 0, z: 0), Point3D(x: 2.5, y: 0, z: 0), Point3D(x: 3.5, y: 0, z: 0)],
                [Point3D(x: 1.5, y: -1, z: 0), Point3D(x: 2.5, y: 0, z: 0), Point3D(x: 3.5, y: 1, z: 0)]])
        let collapsedModel = try sheet(surface: collapsed)
        do {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: collapsedModel)
            throw failure("A collapsed original rectangle published a mesh.")
        } catch let error as KernelError {
            guard error.code == .singularGeometry else { throw error }
        }
        print("ORIGINAL_NONCLAMPED_SINGULAR_REFUSAL_OK")
    }

    private static func verify(_ mesh: Mesh, model: BRepModel,
                               direction: SurfaceParameterDirection, options: TessellationOptions) throws {
        try require(!mesh.positions.isEmpty && mesh.indices.count.isMultiple(of: 3)
                    && mesh.normals.count == mesh.positions.count, "Original rectangle mesh buffers are incomplete.")
        try require(mesh.faceRuns.count == 1 && mesh.faceRuns[0].triangleCount == mesh.indices.count / 3
                    && Set(mesh.faceRuns.map { $0.faceID }) == Set(model.faces.keys),
                    "Original rectangle mesh lost its generating face.")
        for index in mesh.positions.indices {
            let point = mesh.positions[index]
            let parameter = direction == .u ? point.x : point.y
            let expected = try (direction == .u
                ? Vector3D(x: -0.4 * parameter, y: 0, z: 1)
                : Vector3D(x: 0, y: -0.4 * parameter, z: 1)).normalized(tolerance: 1e-12)
            try require(abs(point.z - 0.2 * parameter * parameter) < 1e-10
                        && (mesh.normals[index] - expected).length < 1e-9,
                        "Original rectangle positions or normals differ from the literal polynomial.")
        }
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            guard let a = Int(exactly: mesh.indices[offset]),
                  let b = Int(exactly: mesh.indices[offset + 1]),
                  let c = Int(exactly: mesh.indices[offset + 2]),
                  mesh.positions.indices.contains(a), mesh.positions.indices.contains(b), mesh.positions.indices.contains(c) else {
                throw failure("Original rectangle indices are invalid or unrepresentable.")
            }
            try verifyEdge(mesh.positions[a], mesh.positions[b], direction: direction, options: options)
            try verifyEdge(mesh.positions[b], mesh.positions[c], direction: direction, options: options)
            try verifyEdge(mesh.positions[c], mesh.positions[a], direction: direction, options: options)
        }
    }

    private static func verifyEdge(_ first: Point3D, _ second: Point3D,
                                   direction: SurfaceParameterDirection, options: TessellationOptions) throws {
        guard let edgeLimit = options.maxEdgeLength else {
            throw failure("The literal rectangle witness requires an explicit edge ceiling.")
        }
        let parameter = direction == .u ? (first.x + second.x) * 0.5 : (first.y + second.y) * 0.5
        let deviation = abs((first.z + second.z) * 0.5 - 0.2 * parameter * parameter)
        try require((second - first).length <= edgeLimit * (1 + 1e-9)
                    && deviation <= options.linearTolerance * (1 + 1e-9),
                    "An original rectangle triangle edge violates its caller's fidelity request.")
    }

    private static func surface(direction: SurfaceParameterDirection) -> BSplineSurface3D {
        let xs = [-0.5, 0.5, 1.5]
        let zs = [0.0, 0, 0.4]
        let rows = [0.0, 1.0].map { y in xs.indices.map { Point3D(x: xs[$0], y: y, z: zs[$0]) } }
        if direction == .u {
            return BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [0, 1, 2, 3, 4, 5],
                                    vKnots: [0, 0, 1, 1], controlPoints: rows)
        }
        return BSplineSurface3D(uDegree: 1, vDegree: 2, uKnots: [0, 0, 1, 1],
                                vKnots: [0, 1, 2, 3, 4, 5], controlPoints: xs.indices.map { i in
            rows.map { Point3D(x: $0[i].y, y: $0[i].x, z: $0[i].z) }
        })
    }

    private static func sheet(surface: BSplineSurface3D) throws -> BRepModel {
        let support = Surface3D.bSpline(surface)
        guard case let .closed(u0, u1) = surface.uDomain,
              case let .closed(v0, v1) = surface.vDomain else { throw failure("The original rectangle has no closed native domain.") }
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: v0, uStart: u0, uEnd: u1), .constantU(u: u1, vStart: v0, vEnd: v1),
            .constantV(v: v1, uStart: u1, uEnd: u0), .constantU(u: u0, vStart: v1, vEnd: v0),
        ]
        let vertices = try [(u0, v0), (u1, v0), (u1, v1), (u0, v1)].map {
            Vertex(point: try support.point(u: $0.0, v: $0.1, tolerance: .standard))
        }
        var model = BRepModel()
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        var coedges: [Coedge] = []
        for index in pcurves.indices {
            let curveID = CurveID()
            model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(surface: support, parameterCurve: pcurves[index]))
            let edge = Edge(curveID: curveID, startVertexID: vertices[index].id,
                            endVertexID: vertices[(index + 1) % 4].id, trim: CurveTrim(startParameter: 0, endParameter: 1))
            model.edges[edge.id] = edge
            coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: pcurves[index]))
        }
        let surfaceID = SurfaceID()
        model.geometry.surfaces[surfaceID] = support
        let loop = Loop(coedges: coedges)
        let face = Face(surfaceID: surfaceID, loops: [loop.id])
        let shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.loops[loop.id] = loop
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return model
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw failure(message) }
    }

    private static func failure(_ message: String) -> KernelError {
        KernelError(phase: .validation, code: .topologyFailure, tolerance: .standard, message: message)
    }
}
