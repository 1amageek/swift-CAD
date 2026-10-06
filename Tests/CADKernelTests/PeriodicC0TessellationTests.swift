import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation
import Testing
@testable import CADKernel

@Suite("Original periodic C0 rectangle tessellation")
struct PeriodicC0TessellationTests {
    private let options = TessellationOptions(linearTolerance: 0.01, angularTolerance: 0.15, maxEdgeLength: 0.5)

    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v", "both"], ["base", "negative", "crossing", "shifted", "full"])
    func originalPeriodicPanelsPreserveLiteralGeometryAndClosedSideNormals(axes: String, chart: String) throws {
        let range: (Double, Double)
        switch chart {
        case "negative": range = (-0.5, 0.5)
        case "crossing": range = (3.5, 4.5)
        case "shifted": range = (7.5, 8.5)
        case "full": range = (0, 4)
        default: range = (0.25, 1.75)
        }
        let model = try fixture(axes: axes, range: range, shifted: chart == "shifted")
        let original = model
        let meshes = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        let body = try #require(model.bodies.keys.first), face = try #require(model.faces.keys.first)
        let mesh = try #require(meshes[body])
        #expect(mesh.faceRuns == [Mesh.FaceRun(faceID: face, triangleCount: mesh.indices.count / 3)])
        try verifyWholeLiteralPanels(mesh, axes: axes, options: options)
        if chart != "base" {
            let point = literal(uQuarter: 0, uFraction: axes == "v" ? 0.5 : 0,
                                vQuarter: 0, vFraction: axes == "u" ? 0.5 : 0, axes: axes).point
            let indices = mesh.positions.indices.filter { (mesh.positions[$0] - point).length <= 1e-12 }
            #expect(indices.count >= (axes == "both" ? 4 : 2))
            let normals = indices.map { mesh.normals[$0] }
            var distinct: [Vector3D] = []
            for normal in normals where !distinct.contains(where: { ($0 - normal).length <= 1e-12 }) { distinct.append(normal) }
            #expect(distinct.count == (axes == "both" ? 4 : 2))
        }
        if chart == "full" {
            let loop = try #require(model.loops.values.first)
            #expect(loop.coedges.count == 8)
            #expect(Set(loop.coedges.map(\.edgeID)).count == (axes == "both" ? 4 : 6))
        }
        #expect(model == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func allPanelsRetainCumulativeDuplicateCountsBytesAndPriorReservations() throws {
        let model = try fixture(axes: "both", range: (3.5, 4.5))
        let pair = try fixture(axes: "both", range: (3.5, 4.5), copies: 2)
        let original = pair
        let tessellator = MeshTessellator(tolerance: .standard)
        let mesh = try #require(try tessellator.tessellate(model: model, options: options).values.first)
        let usage = try TessellationUsage(mesh: mesh)
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = usage.vertexCount * 2 - 1
        expectExhaustion(.vertexCount) {
            _ = try MeshTessellator(tolerance: .standard, limits: limits).tessellate(model: pair, options: options)
        }
        let validated = try ValidatedBRepModel(model, tolerance: .standard, validationLevel: .modeling)
        expectExhaustion(.vertexCount) {
            _ = try tessellator.tessellate(validatedModel: validated, options: options, limits: limits, reserving: usage)
        }
        limits = .standard; limits.maximumIndexCount = usage.indexCount - 1
        expectExhaustion(.indexCount) {
            _ = try MeshTessellator(tolerance: .standard, limits: limits).tessellate(model: model, options: options)
        }
        limits = .standard; limits.maximumByteCount = usage.byteCount - 1
        expectExhaustion(.byteCount) {
            _ = try MeshTessellator(tolerance: .standard, limits: limits).tessellate(model: model, options: options)
        }
        #expect(try tessellator.tessellate(model: pair, options: options).count == 2)
        #expect(pair == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v", "both"], [false, true])
    func periodicWidthOvershootNeverPublishesAPartialMesh(axes: String, rounded: Bool) throws {
        let range = rounded ? (-Double(2).nextUp, 2.0) : (0.0, 4.5)
        if rounded { #expect(range.1 - range.0 == 4 && range.0 < -2) }
        let model = try fixture(axes: axes, range: range)
        let original = model
        expectCode(.unsupportedCapability) {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        }
        #expect(model == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["u", "v"], ["translation", "tail"])
    func existingInvalidSourceAndUnprovedTranslationRemainDistinct(axes: String, failure: String) throws {
        let model = try fixture(axes: axes, range: (3.5, 4.5), failure: failure)
        let original = model
        expectCode(failure == "tail" ? .invalidInput : .unsupportedCapability) {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        }
        #expect(model == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledPeriodicPanelPublicationRetainsOriginalSource() async throws {
        let model = try fixture(axes: "both", range: (0, 4)), original = model, options = self.options
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in gate { break }
            return try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        }
        task.cancel(); opened.yield(); opened.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(model == original)
    }

    private struct Literal {
        let point: Point3D
        let du: Vector3D
        let dv: Vector3D
        let mixed: Vector3D
    }

    private struct PanelKey: Hashable {
        let uQuarter: Int
        let vQuarter: Int
    }

    /// Original unit-weight degree-one tensor pieces; neither production basis nor
    /// surface evaluation supplies this source law or the inverse chart oracle.
    private func literal(uQuarter: Int, uFraction: Double, vQuarter: Int, vFraction: Double, axes: String) -> Literal {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        func piece(_ quarter: Int, _ t: Double) -> (x: Double, y: Double, dx: Double, dy: Double) {
            let a = c[quarter], b = c[(quarter + 1) % 4]
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, b.0 - a.0, b.1 - a.1)
        }
        if axes == "both" {
            let a = piece(uQuarter, uFraction), b = piece(vQuarter, vFraction), r = 3 + b.x
            return Literal(point: Point3D(x: r * a.x, y: r * a.y, z: b.y),
                du: Vector3D(x: r * a.dx, y: r * a.dy, z: 0),
                dv: Vector3D(x: b.dx * a.x, y: b.dx * a.y, z: b.dy),
                mixed: Vector3D(x: b.dx * a.dx, y: b.dx * a.dy, z: 0))
        }
        let a = piece(axes == "u" ? uQuarter : vQuarter, axes == "u" ? uFraction : vFraction)
        let tangent = Vector3D(x: a.dx, y: a.dy, z: 0), axial = Vector3D(x: 0, y: 0, z: 1)
        return Literal(point: Point3D(x: a.x, y: a.y, z: axes == "u" ? vFraction : uFraction),
                       du: axes == "u" ? tangent : axial, dv: axes == "u" ? axial : tangent, mixed: .zero)
    }

    private func chart(_ point: Point3D, key: PanelKey, axes: String) -> (u: Double, v: Double) {
        func fraction(_ x: Double, _ y: Double, quarter: Int) -> Double {
            switch quarter { case 0: return y; case 1: return -x; case 2: return -y; default: return x }
        }
        if axes == "both" {
            let radius = abs(point.x) + abs(point.y)
            return (fraction(point.x / radius, point.y / radius, quarter: key.uQuarter),
                    fraction(radius - 3, point.z, quarter: key.vQuarter))
        }
        let t = fraction(point.x, point.y, quarter: axes == "u" ? key.uQuarter : key.vQuarter)
        return axes == "u" ? (t, point.z) : (point.z, t)
    }

    private func verifyWholeLiteralPanels(_ mesh: Mesh, axes: String, options: TessellationOptions) throws {
        #expect(!mesh.indices.isEmpty && mesh.indices.count % 3 == 0)
        var vertices: [PanelKey: Set<Int>] = [:], triangles: [PanelKey: Int] = [:]
        let keys = (axes == "v" ? [0] : Array(0..<4)).flatMap { u in
            (axes == "u" ? [0] : Array(0..<4)).map { PanelKey(uQuarter: u, vQuarter: $0) }
        }
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[offset + $0]) }
            let candidates = keys.filter { key in ids.allSatisfy { id in
                let uv = chart(mesh.positions[id], key: key, axes: axes)
                guard uv.u >= -1e-12, uv.u <= 1 + 1e-12, uv.v >= -1e-12, uv.v <= 1 + 1e-12 else { return false }
                let expected = literal(uQuarter: key.uQuarter, uFraction: uv.u,
                                       vQuarter: key.vQuarter, vFraction: uv.v, axes: axes)
                return (mesh.positions[id] - expected.point).length <= 1e-12
            } }
            #expect(candidates.count == 1, "Each triangle must retain exactly one original smooth panel, never a C0 crossing.")
            let key = try #require(candidates.first)
            let uv = ids.map { chart(mesh.positions[$0], key: key, axes: axes) }
            let u0 = try #require(uv.map(\.u).min()), u1 = try #require(uv.map(\.u).max())
            let v0 = try #require(uv.map(\.v).min()), v1 = try #require(uv.map(\.v).max())
            #expect(u1 > u0 && v1 > v0)
            // A native bilinear grid triangle's whole correspondence error is at
            // most |S_uv|*du*dv/4, attained on its diagonal. Pure second derivatives
            // vanish identically. This analytic bound does not sample acceptance.
            let center = literal(uQuarter: key.uQuarter, uFraction: (u0 + u1) / 2,
                                 vQuarter: key.vQuarter, vFraction: (v0 + v1) / 2, axes: axes)
            #expect(center.mixed.length * (u1 - u0) * (v1 - v0) / 4 <= options.linearTolerance * (1 + 1e-12))
            let expectedNormal = try center.du.cross(center.dv).normalized(tolerance: 1e-300)
            for i in ids.indices {
                let expected = literal(uQuarter: key.uQuarter, uFraction: uv[i].u,
                                       vQuarter: key.vQuarter, vFraction: uv[i].v, axes: axes)
                let n = try expected.du.cross(expected.dv).normalized(tolerance: 1e-300)
                // Every diamond tensor panel has a constant unit normal: its
                // original cross-product is positive radius times one fixed vector.
                #expect((n - expectedNormal).length <= 1e-12)
                #expect((mesh.normals[ids[i]] - n).length <= 1e-12)
                if let maximum = options.maxEdgeLength {
                    let a = mesh.positions[ids[i]], b = mesh.positions[ids[(i + 1) % 3]]
                    #expect((a - b).length <= maximum * (1 + 1e-12))
                }
                vertices[key, default: []].insert(ids[i])
            }
            let winding = (mesh.positions[ids[1]] - mesh.positions[ids[0]]).cross(mesh.positions[ids[2]] - mesh.positions[ids[0]])
            #expect(winding.dot(expectedNormal) > 0)
            triangles[key, default: 0] += 1
        }
        for (key, indices) in vertices {
            let parameters = indices.map { chart(mesh.positions[$0], key: key, axes: axes) }
            let us = Set(parameters.map(\.u)), vs = Set(parameters.map(\.v))
            #expect(indices.count == us.count * vs.count)
            #expect(triangles[key] == 2 * (us.count - 1) * (vs.count - 1))
        }
        #expect(vertices.values.reduce(0) { $0 + $1.count } == mesh.positions.count)
    }

    /// Independently authored coedges retain exact unwrapped UV and actual seam
    /// edge identity. Splitting a full side prevents zero-length topological edges.
    private func fixture(axes: String, range: (Double, Double), shifted: Bool = false,
                         failure: String = "", copies: Int = 1) throws -> BRepModel {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        let net = axes == "both" ? c.map { b in c.map { a in Point3D(x: (3 + b.0) * a.0, y: (3 + b.0) * a.1, z: b.1) } }
            : axes == "u" ? [0.0, 1.0].map { z in c.map { Point3D(x: $0.0, y: $0.1, z: z) } }
            : c.map { a in [0.0, 1.0].map { z in Point3D(x: a.0, y: a.1, z: z) } }
        var spline = try BSplineSurface3D.periodic(uDegree: 1, vDegree: 1,
            uKnots: axes == "v" ? [0, 0, 1, 1] : [0, 1, 2, 3, 4],
            vKnots: axes == "u" ? [0, 0, 1, 1] : [0, 1, 2, 3, 4],
            controlPoints: net, isUPeriodic: axes != "v", isVPeriodic: axes != "u", tolerance: .standard)
        if shifted {
            if spline.isUPeriodic { spline.uPeriodicOrigin = 8 }
            if spline.isVPeriodic { spline.vPeriodicOrigin = 8 }
        }
        if failure == "translation" {
            if axes == "u" { spline.uKnots[0] = spline.uKnots[0].nextUp }
            else { spline.vKnots[0] = spline.vKnots[0].nextUp }
        }
        if failure == "tail" {
            if axes == "u" { spline.controlPoints[0][4].x += 0.125 }
            else { spline.controlPoints[4][0].x += 0.125 }
        }
        let support = Surface3D.bSpline(spline), u = axes == "v" ? (0.0, 1.0) : range, v = axes == "u" ? (0.0, 1.0) : range
        let fullU = spline.isUPeriodic && range.0 == 0 && range.1 == 4,
            fullV = spline.isVPeriodic && range.0 == 0 && range.1 == 4
        let midU = u.0 + (u.1 - u.0) / 2, midV = v.0 + (v.1 - v.0) / 2
        let corners = [(u.0, v.0), (midU, v.0), (u.1, v.0), (u.1, midV),
                       (u.1, v.1), (midU, v.1), (u.0, v.1), (u.0, midV)]
        func point(_ uv: (Double, Double)) -> Point3D {
            let uf = floor(uv.0), vf = floor(uv.1)
            let uq = (Int(uf) % 4 + 4) % 4, vq = (Int(vf) % 4 + 4) % 4
            return literal(uQuarter: uq, uFraction: spline.isUPeriodic ? uv.0 - uf : uv.0,
                           vQuarter: vq, vFraction: spline.isVPeriodic ? uv.1 - vf : uv.1, axes: axes).point
        }
        func pcurve(_ a: (Double, Double), _ b: (Double, Double)) -> SurfaceParameterCurve {
            a.0 == b.0 ? .constantU(u: a.0, vStart: a.1, vEnd: b.1) : .constantV(v: a.1, uStart: a.0, uEnd: b.0)
        }
        var model = BRepModel()
        for _ in 0..<copies {
            var vertices: [SurfaceParameter: Vertex] = [:], edges: [Int: Edge] = [:], coedges: [Coedge] = []
            func vertex(_ uv: (Double, Double)) -> Vertex {
                let key = SurfaceParameter(u: fullU && uv.0 == u.1 ? u.0 : uv.0,
                                           v: fullV && uv.1 == v.1 ? v.0 : uv.1)
                if let old = vertices[key] { return old }
                let created = Vertex(point: point((key.u, key.v))); vertices[key] = created
                return created
            }
            for i in corners.indices {
                let a = corners[i], b = corners[(i + 1) % corners.count], use = pcurve(a, b)
                let start = vertex(a), end = vertex(b)
                let pair: Int?
                if fullV && i == 4 { pair = 1 }
                else if fullV && i == 5 { pair = 0 }
                else if fullU && i == 6 { pair = 3 }
                else if fullU && i == 7 { pair = 2 }
                else { pair = nil }
                if let pair, let edge = edges[pair] {
                    coedges.append(Coedge(edgeID: edge.id, orientation: .reversed, surfaceParameterCurve: use))
                } else {
                    let curveID = CurveID()
                    model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(surface: support, parameterCurve: use))
                    let edge = Edge(curveID: curveID, startVertexID: start.id, endVertexID: end.id,
                                    trim: CurveTrim(startParameter: 0, endParameter: 1))
                    edges[i] = edge; model.edges[edge.id] = edge
                    coedges.append(Coedge(edgeID: edge.id, orientation: .forward, surfaceParameterCurve: use))
                }
            }
            for vertex in vertices.values { model.vertices[vertex.id] = vertex }
            let surfaceID = SurfaceID(), loop = Loop(coedges: coedges), face = Face(surfaceID: surfaceID, loops: [loop.id])
            let shell = Shell(faceIDs: [face.id]), body = Body(sheetShellIDs: [shell.id])
            model.geometry.surfaces[surfaceID] = support; model.loops[loop.id] = loop
            model.faces[face.id] = face; model.shells[shell.id] = shell; model.bodies[body.id] = body
        }
        return model
    }

    private func expectCode(_ code: KernelErrorCode, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Unproved periodic C0 mesh authority was admitted.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected periodic C0 mesh failure: \(error)") }
    }

    private func expectExhaustion(_ resource: TessellationResource, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Periodic C0 mesh exceeded its caller budget.") }
        catch let error as TessellationError {
            guard case let .resourceExhausted(actual, requested, limit) = error else {
                Issue.record("Unexpected tessellation budget failure: \(error)"); return
            }
            #expect(actual == resource && requested > limit)
        } catch { Issue.record("Unexpected periodic C0 resource failure: \(error)") }
    }
}
