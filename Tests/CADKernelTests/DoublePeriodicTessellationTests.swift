import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation
import Testing
@testable import CADKernel

@Suite("Original double-periodic rectangle tessellation")
struct DoublePeriodicTessellationTests {
    private let options = TessellationOptions(linearTolerance: 0.01, angularTolerance: 0.15, maxEdgeLength: 0.5)

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func bothSeamsAndFullPeriodFacesRetainLiteralGeometryAndOwnership(fullPeriod: Bool) throws {
        let range = fullPeriod ? (0.0, 4.0) : (3.5, 4.5)
        let model = try fixture(u: range, v: range)
        let original = model
        let meshes = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        let bodyID = try #require(model.bodies.keys.first)
        let faceID = try #require(model.faces.keys.first)
        let mesh = try #require(meshes[bodyID])
        #expect(mesh.indices.isEmpty == false)
        #expect(mesh.faceRuns == [Mesh.FaceRun(faceID: faceID, triangleCount: mesh.indices.count / 3)])
        try verifyLiteralMesh(mesh)
        for (u, v) in [(range.0, range.0), (range.1, range.1), (4.0, 4.0)] {
            let p = literal(u, v).point
            #expect(mesh.positions.contains { ($0 - p).length <= 1e-12 })
        }
        if fullPeriod {
            for u in [0.5, 1.5, 2.5, 3.5] {
                #expect(mesh.positions.contains { ($0 - literal(u, 0.5).point).length <= 1e-12 })
            }
            // Both native seams reuse actual edge identities with opposite coedge uses.
            let loop = try #require(model.loops.values.first)
            #expect(loop.coedges.count == 8)
            #expect(Set(loop.coedges.map(\.edgeID)).count == 4)
        }
        #expect(model == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [CADGeometry.SurfaceParameterDirection.u, .v], [false, true])
    func eachPeriodicAxisRefusesExactAndRoundedPeriodOvershoot(axis: CADGeometry.SurfaceParameterDirection, rounded: Bool) throws {
        let excessive = rounded ? (-Double(2).nextUp, 2.0) : (0.0, 4.5)
        if rounded { #expect(excessive.1 - excessive.0 == 4 && excessive.0 < -2) }
        let model = try fixture(u: axis == .u ? excessive : (3.5, 4.5),
                                v: axis == .v ? excessive : (3.5, 4.5))
        try model.validate(level: .modeling, tolerance: .standard)
        let original = model
        expectCode(.unsupportedCapability) {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        }
        #expect(model == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["uTranslation", "vTranslation", "uPeriod", "vPeriod", "uC0", "vC0", "uTail", "vTail"])
    func existingSourceErrorsAndNewContinuityRefusalsRemainDistinct(failure: String) throws {
        let model = try fixture(u: (3.5, 4.5), v: (3.5, 4.5), failure: failure)
        let original = model
        if !failure.hasSuffix("Tail") { try model.validate(level: .modeling, tolerance: .standard) }
        if failure == "uC0" || failure == "vC0" {
            let mesh = try #require(try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options).values.first)
            let faceID = try #require(model.faces.keys.first)
            #expect(mesh.faceRuns == [Mesh.FaceRun(faceID: faceID, triangleCount: mesh.indices.count / 3)])
            try verifyLiteralMixedC0Mesh(mesh, uDegree: failure == "uC0" ? 1 : 2,
                                       vDegree: failure == "vC0" ? 1 : 2)
            #expect(model == original)
            return
        }
        expectCode(failure.hasSuffix("Tail") ? .invalidInput : .unsupportedCapability) {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        }
        #expect(model == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func bothAxisAdmissionRetainsCumulativeCountsBytesAndReservations() throws {
        let model = try fixture(u: (3.5, 4.5), v: (3.5, 4.5))
        let pair = try fixture(u: (3.5, 4.5), v: (3.5, 4.5), copies: 2)
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
        limits = .standard
        limits.maximumByteCount = usage.byteCount - 1
        expectExhaustion(.byteCount) {
            _ = try MeshTessellator(tolerance: .standard, limits: limits).tessellate(model: model, options: options)
        }
        #expect(try tessellator.tessellate(model: pair, options: options).count == 2)
        #expect(pair == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationRetainsOriginalDoubleSeamModel() async throws {
        let model = try fixture(u: (0, 4), v: (0, 4))
        let original = model
        let options = self.options
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in gate { break }
            return try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
        }
        task.cancel()
        opened.yield()
        opened.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(model == original)
    }

    private func verifyLiteralMesh(_ mesh: Mesh) throws {
        var vertexError = 0.0, normalError = 0.0, interiorError = 0.0, angle = 0.0, edgeLength = 0.0
        func chart(_ p: Point3D) -> (u: Double, v: Double) {
            let u = cardinalParameter(x: p.x, y: p.y)
            let a = cardinal(u)
            let radius = abs(a.x) >= abs(a.y) ? p.x / a.x : p.y / a.y
            return (u, cardinalParameter(x: radius - 3, y: p.z))
        }
        for index in mesh.positions.indices {
            let uv = chart(mesh.positions[index]), expected = literal(uv.u, uv.v)
            vertexError = max(vertexError, (mesh.positions[index] - expected.point).length)
            normalError = max(normalError, (mesh.normals[index] - expected.normal).length)
        }
        let barycentrics = [(1.0 / 3, 1.0 / 3, 1.0 / 3), (0.5, 0.5, 0.0),
                            (0.5, 0.0, 0.5), (0.0, 0.5, 0.5)]
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[offset + $0]) }
            let p = ids.map { mesh.positions[$0] }
            for i in 0..<3 { edgeLength = max(edgeLength, (p[i] - p[(i + 1) % 3]).length) }
            for (a, b, c) in barycentrics {
                let point = Point3D(x: a * p[0].x + b * p[1].x + c * p[2].x,
                                    y: a * p[0].y + b * p[1].y + c * p[2].y,
                                    z: a * p[0].z + b * p[1].z + c * p[2].z)
                let uv = chart(point), expected = literal(uv.u, uv.v)
                interiorError = max(interiorError, (point - expected.point).length)
                for id in ids {
                    angle = max(angle, atan2(expected.normal.cross(mesh.normals[id]).length,
                                             expected.normal.dot(mesh.normals[id])))
                }
            }
        }
        #expect(vertexError <= 1e-12)
        #expect(normalError <= 1e-11)
        #expect(interiorError <= options.linearTolerance)
        #expect(angle <= options.angularTolerance)
        let maximumEdgeLength = try #require(options.maxEdgeLength)
        #expect(edgeLength <= maximumEdgeLength)
    }

    /// Inverts the literal cardinal parabola along a ray, independently of CADGeometry.
    private func cardinalParameter(x: Double, y: Double, degree: Int = 2) -> Double {
        if degree == 1 {
            let radius = abs(x) + abs(y)
            if x >= 0 && y >= 0 { return y / radius }
            if x < 0 && y >= 0 { return 1 - x / radius }
            if x <= 0 && y < 0 { return 2 - y / radius }
            return 3 + x / radius
        }
        let quadrant: Int, minor: Double, major: Double
        if abs(y) >= abs(x) {
            if y >= 0 { (quadrant, minor, major) = (0, x, y) }
            else { (quadrant, minor, major) = (2, -x, -y) }
        } else if x < 0 { (quadrant, minor, major) = (1, y, -x) }
        else { (quadrant, minor, major) = (3, -y, x) }
        let ratio = minor / major
        let originalMinor = 1.5 * ratio / (1 + sqrt(1 + 3 * ratio * ratio))
        return Double(quadrant) + 0.5 - originalMinor
    }

    private func cardinal(_ parameter: Double, degree: Int = 2, owningCell: Int? = nil) -> (x: Double, y: Double, dx: Double, dy: Double) {
        let cell = owningCell ?? Int(floor(parameter)), t = parameter - Double(cell)
        let x = degree == 2 ? 0.5 - t : 1 - t
        let y = degree == 2 ? 0.5 + t - t * t : t
        let dx = -1.0, dy = degree == 2 ? 1 - 2 * t : 1
        switch (cell % 4 + 4) % 4 {
        case 0: return (x, y, dx, dy)
        case 1: return (-y, x, -dy, dx)
        case 2: return (-x, -y, -dx, -dy)
        default: return (y, -x, dy, -dx)
        }
    }

    private func literal(_ u: Double, _ v: Double, uDegree: Int = 2, vDegree: Int = 2,
                         owningUCell: Int? = nil, owningVCell: Int? = nil) -> (point: Point3D, normal: Vector3D) {
        let a = cardinal(u, degree: uDegree, owningCell: owningUCell)
        let b = cardinal(v, degree: vDegree, owningCell: owningVCell), r = 3 + b.x
        let point = Point3D(x: r * a.x, y: r * a.y, z: b.y)
        let du = Vector3D(x: r * a.dx, y: r * a.dy, z: 0)
        let dv = Vector3D(x: b.dx * a.x, y: b.dx * a.y, z: b.dy)
        let cross = du.cross(dv)
        return (point, cross / cross.length)
    }

    private func verifyLiteralMixedC0Mesh(_ mesh: Mesh, uDegree: Int, vDegree: Int) throws {
        #expect(!mesh.indices.isEmpty)
        func chart(_ point: Point3D) -> (u: Double, v: Double) {
            let u = cardinalParameter(x: point.x, y: point.y, degree: uDegree)
            let a = cardinal(u, degree: uDegree)
            let radius = abs(a.x) >= abs(a.y) ? point.x / a.x : point.y / a.y
            return (u, cardinalParameter(x: radius - 3, y: point.z, degree: vDegree))
        }
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[offset + $0]) }
            let points = ids.map { mesh.positions[$0] }
            let center = Point3D(x: points.reduce(0) { $0 + $1.x } / 3,
                                 y: points.reduce(0) { $0 + $1.y } / 3,
                                 z: points.reduce(0) { $0 + $1.z } / 3)
            let central = chart(center), uCell = Int(floor(central.u)), vCell = Int(floor(central.v))
            let parameters = points.map { point in
                let uv = chart(point)
                return (u: uv.u < Double(uCell) - 1e-12 ? uv.u + 4 : uv.u,
                        v: uv.v < Double(vCell) - 1e-12 ? uv.v + 4 : uv.v)
            }
            for index in ids.indices {
                let uv = parameters[index]
                #expect(uv.u >= Double(uCell) - 1e-12 && uv.u <= Double(uCell + 1) + 1e-12)
                #expect(uv.v >= Double(vCell) - 1e-12 && uv.v <= Double(vCell + 1) + 1e-12)
                let expected = literal(uv.u, uv.v, uDegree: uDegree, vDegree: vDegree,
                                       owningUCell: uCell, owningVCell: vCell)
                #expect((points[index] - expected.point).length <= 1e-12)
                #expect((mesh.normals[ids[index]] - expected.normal).length <= 1e-11)
                let maximum = try #require(options.maxEdgeLength)
                #expect((points[index] - points[(index + 1) % 3]).length <= maximum)
            }
            let us = parameters.map(\.u), vs = parameters.map(\.v)
            let u0 = try #require(us.min()), u1 = try #require(us.max())
            let v0 = try #require(vs.min()), v1 = try #require(vs.max())
            let du = u1 - u0, dv = v1 - v0
            // The literal degree-(1,2)/(2,1) pieces have |S_uu| <= 8,
            // |S_uv| <= sqrt(2), |S_vv| <= 2, with the linear-axis pure
            // derivative identically zero. Barycentric variance/covariance
            // bounds certify every point of each grid triangle, not samples.
            let uu = uDegree == 2 ? 8.0 : 0.0, vv = vDegree == 2 ? 2.0 : 0.0
            #expect((uu * du * du + 2 * sqrt(2) * du * dv + vv * dv * dv) / 8 <= options.linearTolerance)
            // After cancelling positive radius, the normal depends only on
            // the quadratic axis and its derivative norm is at most 2*sqrt(2).
            #expect(2 * sqrt(2) * (uDegree == 2 ? du : dv) <= options.angularTolerance)
            let expected = literal((u0 + u1) / 2, (v0 + v1) / 2, uDegree: uDegree, vDegree: vDegree,
                                   owningUCell: uCell, owningVCell: vCell)
            #expect((points[1] - points[0]).cross(points[2] - points[0]).dot(expected.normal) > 0)
        }
    }

    /// Exact native rectangle sides, split before closed endpoints. Opposite seam uses
    /// retain one original EdgeID and opposite orientation; no nearest chart unwrap.
    private func fixture(u: (Double, Double), v: (Double, Double), failure: String = "", copies: Int = 1) throws -> BRepModel {
        let uDegree = failure == "uC0" ? 1 : 2, vDegree = failure == "vC0" ? 1 : 2
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        let net = c.map { b in c.map { a in Point3D(x: (3 + b.0) * a.0, y: (3 + b.0) * a.1, z: b.1) } }
        var spline = try BSplineSurface3D.periodic(uDegree: uDegree, vDegree: vDegree,
            uKnots: [0, 1, 2, 3, 4], vKnots: [0, 1, 2, 3, 4], controlPoints: net,
            isUPeriodic: true, isVPeriodic: true, tolerance: .standard)
        if failure == "uTranslation" { spline.uKnots[0] = spline.uKnots[0].nextUp }
        if failure == "vTranslation" { spline.vKnots[0] = spline.vKnots[0].nextUp }
        if failure == "uPeriod" { spline.uKnots[2] = -Double.leastNonzeroMagnitude }
        if failure == "vPeriod" { spline.vKnots[2] = -Double.leastNonzeroMagnitude }
        if failure == "uTail" { spline.controlPoints[0][4].x += 0.125 }
        if failure == "vTail" { spline.controlPoints[4][0].x += 0.125 }
        let support = Surface3D.bSpline(spline)
        let fullU = u.0 == 0 && u.1 == 4, fullV = v.0 == 0 && v.1 == 4
        let midU = u.0 + (u.1 - u.0) * 0.5, midV = v.0 + (v.1 - v.0) * 0.5
        let corners = [(u.0, v.0), (midU, v.0), (u.1, v.0), (u.1, midV),
                       (u.1, v.1), (midU, v.1), (u.0, v.1), (u.0, midV)]
        func pcurve(_ a: (Double, Double), _ b: (Double, Double)) -> SurfaceParameterCurve {
            a.0 == b.0 ? .constantU(u: a.0, vStart: a.1, vEnd: b.1)
                       : .constantV(v: a.1, uStart: a.0, uEnd: b.0)
        }
        var model = BRepModel()
        for _ in 0..<copies {
            var vertices: [SurfaceParameter: Vertex] = [:], edges: [Int: Edge] = [:], coedges: [Coedge] = []
            func vertex(_ uv: (Double, Double)) -> Vertex {
                let key = SurfaceParameter(u: fullU && uv.0 == u.1 ? u.0 : uv.0,
                                           v: fullV && uv.1 == v.1 ? v.0 : uv.1)
                if let existing = vertices[key] { return existing }
                let created = Vertex(point: literal(key.u, key.v, uDegree: uDegree, vDegree: vDegree).point)
                vertices[key] = created
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
                    edges[i] = edge
                    model.edges[edge.id] = edge
                    coedges.append(Coedge(edgeID: edge.id, orientation: .forward, surfaceParameterCurve: use))
                }
            }
            for vertex in vertices.values { model.vertices[vertex.id] = vertex }
            let surfaceID = SurfaceID(), loop = Loop(coedges: coedges)
            let face = Face(surfaceID: surfaceID, loops: [loop.id])
            let shell = Shell(faceIDs: [face.id])
            let sheetBody = Body(sheetShellIDs: [shell.id])
            model.geometry.surfaces[surfaceID] = support
            model.loops[loop.id] = loop
            model.faces[face.id] = face
            model.shells[shell.id] = shell
            model.bodies[sheetBody.id] = sheetBody
        }
        return model
    }

    private func expectCode(_ code: KernelErrorCode, operation: () throws -> Void) {
        do { try operation(); Issue.record("Unproved double-periodic mesh admission succeeded.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected double-periodic mesh failure: \(error)") }
    }

    private func expectExhaustion(_ resource: TessellationResource, operation: () throws -> Void) {
        do { try operation(); Issue.record("Double-periodic mesh exceeded its cumulative budget.") }
        catch let error as TessellationError {
            guard case let .resourceExhausted(actual, requested, limit) = error else {
                Issue.record("Unexpected tessellation budget failure: \(error)"); return
            }
            #expect(actual == resource && requested > limit)
        } catch { Issue.record("Unexpected double-periodic resource failure: \(error)") }
    }
}
