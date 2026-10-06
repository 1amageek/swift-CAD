import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
import Foundation

/// Executes literal original rectangular mesh laws through the public kernel.
enum RectangularBSplineMeshSmoke {
    static func run() async throws {
        let coarse = TessellationOptions(linearTolerance: 1e-3, angularTolerance: 0.08, maxEdgeLength: 0.25)
        for transpose in [false, true] {
            let model = try sheet(surface: quadratic(transpose: transpose, rise: 0.2))
            let original = model
            let first = try mesh(model, options: coarse)
            try checkGraph(first, rise: 0.2, transpose: transpose, options: coarse)
            let tight = TessellationOptions(linearTolerance: 1e-5, angularTolerance: 0.08, maxEdgeLength: 0.25)
            let refined = try mesh(model, options: tight)
            try checkGraph(refined, rise: 0.2, transpose: transpose, options: tight)
            try require(refined.positions.count > first.positions.count, "Original nonclamped position tolerance did not refine the public mesh.")
            let angleOptions = TessellationOptions(linearTolerance: 1e-3, angularTolerance: 0.005, maxEdgeLength: 0.25)
            let angular = try mesh(model, options: angleOptions)
            try checkGraph(angular, rise: 0.2, transpose: transpose, options: angleOptions)
            try require(angular.positions.count > first.positions.count, "Original nonclamped angular tolerance did not refine the public mesh.")
            let curved = try mesh(sheet(surface: quadratic(transpose: transpose, rise: 1.6)), options: coarse)
            try checkGraph(curved, rise: 1.6, transpose: transpose, options: coarse)
            try require(curved.positions.count > first.positions.count, "Original nonclamped curvature did not refine the public mesh.")
            try require(model == original, "Public mesh changed original nonclamped source geometry or topology.")
            let bodyID = try firstBody(model)
            let extracted = try BRepBodySubmodelExtractor().extract(bodyIDs: [bodyID], from: model)
            try require(try mesh(extracted, options: coarse) == first, "Original mesh FaceRun/extraction identity changed.")
        }
        // Unequal original weights change the parameter law while the exact image
        // remains the unit planar rectangle with a constant original normal.
        let rational = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]], weights: [[2, 1], [2, 1]])
        let rationalMesh = try mesh(sheet(surface: rational), options: coarse)
        for i in rationalMesh.positions.indices {
            let p = rationalMesh.positions[i]
            try require(p.z == 0 && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1,
                        "Original unequal-weight rectangle left its literal plane/domain.")
            try require((rationalMesh.normals[i] - Vector3D.unitZ).length <= 1e-12, "Original rational planar normal changed.")
        }
        try checkEdges(rationalMesh, options: coarse)
        for full in [false, true] {
            let model = try mixedSheet(full: full)
            let original = model
            let result = try mesh(model, options: coarse)
            try checkMixed(result, options: coarse)
            try require(model == original, "Public mesh changed original mixed-periodic geometry or topology.")
        }
        let model = try sheet(surface: quadratic(transpose: false, rise: 0.2))
        let original = model
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 1
        do {
            _ = try MeshTessellator(tolerance: .standard, limits: limits).tessellate(model: model, options: coarse)
            throw failure("The public original rectangle ignored caller storage admission.")
        } catch let error as TessellationError {
            guard case .resourceExhausted(.vertexCount, _, _) = error else { throw error }
        }
        // Preserve nonzero boundary edges while the first original U panel has exactly zero tangent.
        let collapsed = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [-1, 0, 0.5, 1, 2], vKnots: [0, 0, 1, 1],
            controlPoints: [[.origin, .origin, Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]])
        do {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: sheet(surface: collapsed), options: coarse)
            throw failure("A singular original rectangle published a mesh.")
        } catch let error as KernelError {
            guard error.code == .singularGeometry else { throw error }
        }
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in gate { break }
            return try MeshTessellator(tolerance: .standard).tessellate(model: model, options: coarse)
        }
        task.cancel(); opened.yield(); opened.finish()
        do {
            _ = try await task.value
            throw failure("Cancelled public original rectangle tessellation published a mesh.")
        } catch is CancellationError { }
        try require(model == original, "Refused public mesh changed original inputs.")
        print("RectangularBSplineMeshSmoke passed")
    }

    private static func quadratic(transpose: Bool, rise: Double) -> BSplineSurface3D {
        let x = [-0.5, 0.5, 1.5], z = [0.0, 0.0, 2 * rise]
        let rows = [0.0, 1.0].map { y in x.indices.map { i in Point3D(x: x[i], y: y, z: z[i]) } }
        return BSplineSurface3D(uDegree: transpose ? 1 : 2, vDegree: transpose ? 2 : 1,
            uKnots: transpose ? [0, 0, 1, 1] : [0, 1, 2, 3, 4, 5],
            vKnots: transpose ? [0, 1, 2, 3, 4, 5] : [0, 0, 1, 1],
            controlPoints: transpose ? x.indices.map { i in rows.map { Point3D(x: $0[i].y, y: $0[i].x, z: $0[i].z) } } : rows)
    }

    private static func sheet(surface: BSplineSurface3D) throws -> BRepModel {
        guard case let .closed(u0, u1) = surface.uDomain, case let .closed(v0, v1) = surface.vDomain else {
            throw failure("The original portable rectangular fixture has no closed native domain.")
        }
        return try sheet(surface: surface, corners: [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], fullPeriod: false)
    }

    private static func mixedSheet(full: Bool) throws -> BRepModel {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0), (1.0, 0.0)]
        let radius = [1.0, 1.125, 1.0], height = [0.0, 0.5, 1.0]
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [-1, 0, 1, 2, 3, 4, 5], vKnots: [-1, 0, 0.5, 1, 2],
            controlPoints: radius.indices.map { j in c.map { Point3D(x: radius[j] * $0.0, y: radius[j] * $0.1, z: height[j]) } }, isUPeriodic: true)
        let corners: [(Double, Double)] = full ? [(0, 0), (2, 0), (4, 0), (4, 1), (2, 1), (0, 1)]
            : [(3.5, 0), (4.5, 0), (4.5, 1), (3.5, 1)]
        return try sheet(surface: surface, corners: corners, fullPeriod: full)
    }

    private static func sheet(surface: BSplineSurface3D, corners: [(Double, Double)], fullPeriod: Bool) throws -> BRepModel {
        let support = Surface3D.bSpline(surface)
        func pc(_ a: (Double, Double), _ b: (Double, Double)) -> SurfaceParameterCurve {
            a.0 == b.0 ? .constantU(u: a.0, vStart: a.1, vEnd: b.1) : .constantV(v: a.1, uStart: a.0, uEnd: b.0)
        }
        var model = BRepModel(), vertices: [SurfaceParameter: Vertex] = [:], seam: Edge?
        func vertex(_ p: (Double, Double)) throws -> Vertex {
            let key = SurfaceParameter(u: fullPeriod ? p.0.truncatingRemainder(dividingBy: 4) : p.0, v: p.1)
            if let old = vertices[key] { return old }
            let created = Vertex(point: try support.point(u: p.0, v: p.1, tolerance: .standard))
            vertices[key] = created; return created
        }
        var coedges: [Coedge] = []
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count], use = pc(a, b)
            let start = try vertex(a), end = try vertex(b)
            if fullPeriod && i == 5, let seam {
                coedges.append(Coedge(edgeID: seam.id, orientation: .reversed, surfaceParameterCurve: use)); continue
            }
            let curveID = CurveID(), stored = fullPeriod && i == 2 ? pc((0, 0), (0, 1)) : use
            model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(surface: support, parameterCurve: stored))
            let edge = Edge(curveID: curveID, startVertexID: start.id, endVertexID: end.id, trim: CurveTrim(startParameter: 0, endParameter: 1))
            model.edges[edge.id] = edge
            if fullPeriod && i == 2 {
                seam = edge
                coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: .periodicTranslation(base: stored, uShift: 4, vShift: 0)))
            } else { coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: use)) }
        }
        for vertex in vertices.values { model.vertices[vertex.id] = vertex }
        let surfaceID = SurfaceID(), loop = Loop(coedges: coedges), face = Face(surfaceID: surfaceID, loops: [loop.id])
        let shell = Shell(faceIDs: [face.id]), body = Body(sheetShellIDs: [shell.id])
        model.geometry.surfaces[surfaceID] = support; model.loops[loop.id] = loop
        model.faces[face.id] = face; model.shells[shell.id] = shell; model.bodies[body.id] = body
        return model
    }

    private static func checkGraph(_ mesh: Mesh, rise: Double, transpose: Bool, options: TessellationOptions) throws {
        try require(!mesh.indices.isEmpty, "The public original rectangular mesh is empty.")
        for i in mesh.positions.indices {
            let p = mesh.positions[i], t = transpose ? p.y : p.x
            let n = try Vector3D(x: transpose ? 0 : -2 * rise * t, y: transpose ? -2 * rise * t : 0, z: 1).normalized(tolerance: 1e-300)
            try require(abs(p.z - rise * t * t) <= 1e-12 && (n - mesh.normals[i]).length <= 1e-11,
                        "Original nonclamped vertex position/normal disagrees with the literal graph.")
        }
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[offset + $0]) }, p = ids.map { mesh.positions[$0] }
            for weights in [(0.5, 0.5, 0.0), (0.5, 0.0, 0.5), (0.0, 0.5, 0.5), (1.0 / 3, 1.0 / 3, 1.0 / 3)] {
                let x = weights.0 * p[0].x + weights.1 * p[1].x + weights.2 * p[2].x
                let y = weights.0 * p[0].y + weights.1 * p[1].y + weights.2 * p[2].y
                let z = weights.0 * p[0].z + weights.1 * p[1].z + weights.2 * p[2].z, t = transpose ? y : x
                let n = try Vector3D(x: transpose ? 0 : -2 * rise * t, y: transpose ? -2 * rise * t : 0, z: 1).normalized(tolerance: 1e-300)
                try require(abs(z - rise * t * t) <= options.linearTolerance, "Original triangle interior exceeds the caller position allowance.")
                for id in ids { try require(atan2(n.cross(mesh.normals[id]).length, n.dot(mesh.normals[id])) <= options.angularTolerance, "Original triangle normal exceeds the caller angle allowance.") }
            }
        }
        try checkEdges(mesh, options: options)
    }

    private static func checkMixed(_ mesh: Mesh, options: TessellationOptions) throws {
        try require(!mesh.indices.isEmpty, "The public mixed native mesh is empty.")
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[offset + $0]) }, p = ids.map { mesh.positions[$0] }
            let sx = p.reduce(0.0) { $0 + $1.x } >= 0 ? 1.0 : -1.0, sy = p.reduce(0.0) { $0 + $1.y } >= 0 ? 1.0 : -1.0
            let z0 = p.reduce(Double.infinity) { min($0, $1.z) }, z1 = p.reduce(-Double.infinity) { max($0, $1.z) }
            try require(!(z0 < 0.5 && z1 > 0.5), "A mixed native triangle crosses the original C0 open knot.")
            let normal = try Vector3D(x: sx, y: sy, z: z1 <= 0.5 ? -0.25 : 0.25).normalized(tolerance: 1e-300)
            for id in ids {
                let q = mesh.positions[id], r = 1 + 0.25 * min(q.z, 1 - q.z)
                try require(abs(sx * q.x + sy * q.y - r) <= 1e-12 && sx * q.x >= -1e-12 && sy * q.y >= -1e-12,
                            "A mixed native triangle left its literal original diamond plane.")
                try require((normal - mesh.normals[id]).length <= 1e-11, "Mixed native closed-side normal ownership changed.")
            }
        }
        // Each admitted triangle has three vertices in one literal affine plane;
        // all barycentric interiors therefore have zero geometric/normal error.
        try checkEdges(mesh, options: options)
    }

    private static func checkEdges(_ mesh: Mesh, options: TessellationOptions) throws {
        guard let limit = options.maxEdgeLength else { return }
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let p = (0..<3).map { mesh.positions[Int(mesh.indices[offset + $0])] }
            for i in 0..<3 { try require((p[(i + 1) % 3] - p[i]).length <= limit, "An original triangle diagonal/edge exceeds the caller length allowance.") }
        }
    }

    private static func mesh(_ model: BRepModel, options: TessellationOptions) throws -> Mesh {
        let result = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        guard let mesh = result.values.first, let faceID = model.faces.keys.first,
              mesh.faceRuns == [Mesh.FaceRun(faceID: faceID, triangleCount: mesh.indices.count / 3)] else {
            throw failure("Original public mesh lost its face-run owner.")
        }
        return mesh
    }

    private static func firstBody(_ model: BRepModel) throws -> BodyID {
        guard let id = model.bodies.keys.first else { throw failure("The original portable fixture has no body.") }
        return id
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw failure(message) }
    }

    private static func failure(_ message: String) -> KernelError {
        KernelError(phase: .validation, code: .invalidInput, tolerance: .standard, message: message)
    }
}
