import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Original nonclamped rectangular mesh")
struct OriginalNativeRectangularMeshTests {
    private let options = TessellationOptions(
        linearTolerance: 0.002, angularTolerance: 0.08, maxEdgeLength: 0.25)

    @Test(.timeLimit(.minutes(1)))
    func literalQuadraticUUsesTheOriginalTwoToThreeDomain() throws {
        try verifyQuadratic(uNonclamped: true, vNonclamped: false)
    }

    @Test(.timeLimit(.minutes(1)))
    func literalQuadraticVUsesTheOriginalTwoToThreeDomain() throws {
        try verifyQuadratic(uNonclamped: false, vNonclamped: true)
    }

    @Test(.timeLimit(.minutes(1)))
    func bothNonclampedAxesKeepTheirOriginalParameters() throws {
        try verifyQuadratic(uNonclamped: true, vNonclamped: true)
    }

    @Test(.timeLimit(.minutes(1)))
    func roundedSpanArithmeticStillEmitsBothExactNativeBoundaries() throws {
        let lower = -1.0, upper = 0.2
        #expect(lower + (upper - lower) != upper)
        #expect(RectangularBSplineMesh.station(lowerBound: lower, upperBound: upper,
            index: 0, count: 16) == lower)
        #expect(RectangularBSplineMesh.station(lowerBound: lower, upperBound: upper,
            index: 16, count: 16) == upper)
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [-2, lower, upper, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [Point3D(x: lower, y: 0, z: 0), Point3D(x: upper, y: 0, z: 0)],
                [Point3D(x: lower, y: 1, z: 0), Point3D(x: upper, y: 1, z: 0)]])
        // The original four constant-U/V pcurves retain their stored endpoints;
        // admission must not replace them with rounded normalized-fraction evaluation.
        let model = try Self.sheet(surface: surface)
        let mesh = try #require(try MeshTessellator(tolerance: .standard)
            .tessellate(model: model, options: options).values.first)
        let sourceStart = try surface.point(u: lower, v: 0, tolerance: .standard)
        let sourceEnd = try surface.point(u: upper, v: 1, tolerance: .standard)
        #expect(mesh.positions.contains(sourceStart))
        #expect(mesh.positions.contains(sourceEnd))
        let lowerBoundary = Set(mesh.positions.filter { $0.x == lower }.map(\.y))
        let upperBoundary = Set(mesh.positions.filter { $0.x == upper }.map(\.y))
        #expect(lowerBoundary == upperBoundary)
        #expect(upperBoundary.count > 2)
        #expect(mesh.positions.allSatisfy { (lower...upper).contains($0.x) })
        for triangle in 0..<(mesh.indices.count / 3) {
            let corners = (0..<3).map { mesh.positions[Int(mesh.indices[3 * triangle + $0])] }
            for edge in 0..<3 {
                #expect((corners[(edge + 1) % 3] - corners[edge]).length <= 0.25 * (1 + 1e-12))
            }
        }
        try verifyProvenance(mesh, model: model)
    }

    @Test(.timeLimit(.minutes(1)))
    func c0PanelsKeepBothOneSidedNormalsAndCompatibleStations() throws {
        let surface = Self.c0Surface()
        let model = try Self.sheet(surface: surface)
        let mesh = try #require(try MeshTessellator(tolerance: .standard)
            .tessellate(model: model, options: options).values.first)
        var leftStations: Set<Double> = [], rightStations: Set<Double> = []
        var measuredLeft = false, measuredRight = false
        for triangle in 0..<(mesh.indices.count / 3) {
            let ids = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            let corners = ids.map { mesh.positions[$0] }
            let left = corners.reduce(0.0) { $0 + $1.x } / 3 < 2.5
            #expect(corners.allSatisfy { left ? $0.x <= 2.5 : $0.x >= 2.5 })
            let expected = try Vector3D(x: left ? -0.5 : 0.5, y: 0, z: 1)
                .normalized(tolerance: 1e-300)
            for id in ids {
                let p = mesh.positions[id]
                #expect(abs(p.z - (p.x <= 2.5 ? 0.5 * (p.x - 2) : 0.5 * (3 - p.x))) <= 1e-12)
                #expect((mesh.normals[id] - expected).length <= 1e-11)
                if p.x == 2.5 {
                    if left { leftStations.insert(p.y); measuredLeft = true }
                    else { rightStations.insert(p.y); measuredRight = true }
                }
            }
        }
        #expect(measuredLeft && measuredRight)
        #expect(leftStations == rightStations)
        #expect(leftStations.count > 2)
        try verifyProvenance(mesh, model: model)
    }

    @Test(.timeLimit(.minutes(1)))
    func twoAxisC0CrossingKeepsFourOriginalNormalOwners() throws {
        let coordinates = [2.0, 2.5, 3.0], heights = [0.0, 0.25, 0.0]
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [1, 2, 2.5, 3, 4], vKnots: [1, 2, 2.5, 3, 4],
            controlPoints: coordinates.indices.map { j in coordinates.indices.map { i in
                Point3D(x: coordinates[i], y: coordinates[j], z: heights[i] + heights[j])
            } })
        let model = try Self.sheet(surface: surface)
        let mesh = try #require(try MeshTessellator(tolerance: .standard)
            .tessellate(model: model, options: options).values.first)
        var crossingNormalSigns: Set<Int> = []
        for triangle in 0..<(mesh.indices.count / 3) {
            let ids = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            let corners = ids.map { mesh.positions[$0] }
            let left = corners.reduce(0.0) { $0 + $1.x } / 3 < 2.5
            let bottom = corners.reduce(0.0) { $0 + $1.y } / 3 < 2.5
            let expected = try Vector3D(x: left ? -0.5 : 0.5, y: bottom ? -0.5 : 0.5, z: 1)
                .normalized(tolerance: 1e-300)
            #expect(corners.allSatisfy { (left ? $0.x <= 2.5 : $0.x >= 2.5)
                && (bottom ? $0.y <= 2.5 : $0.y >= 2.5) })
            for id in ids {
                let p = mesh.positions[id]
                let height = 0.5 * min(p.x - 2, 3 - p.x) + 0.5 * min(p.y - 2, 3 - p.y)
                #expect(abs(p.z - height) <= 1e-12)
                #expect((mesh.normals[id] - expected).length <= 1e-11)
                if p.x == 2.5 && p.y == 2.5 {
                    crossingNormalSigns.insert((left ? 0 : 1) + (bottom ? 0 : 2))
                }
            }
        }
        #expect(crossingNormalSigns == [0, 1, 2, 3])
        try verifyProvenance(mesh, model: model)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCollapsedOriginalPanelRefusesInsteadOfUsingGridNormalFallback() throws {
        // The original graph S(u,v)=(u,(u-2.5)*v,0) has zero tangent area at u=2.5.
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 1, 2, 3, 4, 5], vKnots: [0, 0, 1, 1], controlPoints: [
                [Point3D(x: 1.5, y: 0, z: 0), Point3D(x: 2.5, y: 0, z: 0), Point3D(x: 3.5, y: 0, z: 0)],
                [Point3D(x: 1.5, y: -1, z: 0), Point3D(x: 2.5, y: 0, z: 0), Point3D(x: 3.5, y: 1, z: 0)]])
        let model = try Self.sheet(surface: surface)
        do {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
            Issue.record("Expected the collapsed original native panel to fail.")
        } catch let error as KernelError {
            #expect(error.code == .singularGeometry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonrectangularNonclampedTrimsFailWithTypedUnsupportedCapability() throws {
        let surface = Self.quadraticSurface(uNonclamped: true, vNonclamped: false)
        let curves: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 2, uEnd: 3),
            .affine(origin: Point2D(x: 3, y: 0), direction: Point2D(x: -0.2, y: 1), startParameter: 0, endParameter: 1),
            .constantV(v: 1, uStart: 2.8, uEnd: 2),
            .constantU(u: 2, vStart: 1, vEnd: 0)]
        let model = try Self.sheet(surface: surface, curves: curves)
        do {
            _ = try MeshTessellator(tolerance: .standard).tessellate(model: model, options: options)
            Issue.record("Expected nonrectangular original trims to fail.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func callerStorageAndCumulativeReservationRefuseAtomically() throws {
        let model = try Self.sheet(surface: Self.quadraticSurface(uNonclamped: true, vNonclamped: true))
        let validated = try ValidatedBRepModel(model, tolerance: .standard, validationLevel: .modeling)
        let mesh = try #require(try MeshTessellator(tolerance: .standard)
            .tessellate(validatedModel: validated, options: options).values.first)
        let usage = try TessellationUsage(mesh: mesh)
        var limited = TessellationLimits.standard
        limited.maximumByteCount = usage.byteCount - 1
        do {
            _ = try MeshTessellator(tolerance: .standard).tessellate(
                validatedModel: validated, options: options, limits: limited, reserving: .zero)
            Issue.record("Expected caller byte storage refusal.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(resource, requested, limit) = error else {
                Issue.record("Expected typed resource exhaustion."); return
            }
            #expect(resource == .byteCount)
            #expect(requested >= usage.byteCount)
            #expect(limit == usage.byteCount - 1)
        }
        limited.maximumByteCount = usage.byteCount
        do {
            _ = try MeshTessellator(tolerance: .standard).tessellate(
                validatedModel: validated, options: options, limits: limited, reserving: usage)
            Issue.record("Expected cumulative reservation refusal.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(resource, requested, limit) = error else {
                Issue.record("Expected typed cumulative resource exhaustion."); return
            }
            #expect(resource == .byteCount)
            #expect(requested >= usage.byteCount * 2)
            #expect(limit == usage.byteCount)
        }
        #expect(validated.model == model)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationPropagatesBeforeOriginalPanelWork() async throws {
        let model = try Self.sheet(surface: Self.c0Surface())
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate { break }
            return try MeshTessellator(tolerance: .standard).tessellate(model: model)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func verifyQuadratic(uNonclamped: Bool, vNonclamped: Bool) throws {
        let model = try Self.sheet(surface: Self.quadraticSurface(
            uNonclamped: uNonclamped, vNonclamped: vNonclamped))
        let original = model
        let mesh = try #require(try MeshTessellator(tolerance: .standard)
            .tessellate(model: model, options: options).values.first)
        let height: (Double, Double) -> Double = { x, y in
            (uNonclamped ? 0.125 * x * x : 0) + (vNonclamped ? 0.0625 * y * y : 0)
        }
        let normal: (Double, Double) throws -> Vector3D = { x, y in
            try Vector3D(x: uNonclamped ? -0.25 * x : 0,
                         y: vNonclamped ? -0.125 * y : 0, z: 1).normalized(tolerance: 1e-300)
        }
        #expect(mesh.indices.count > 6)
        for index in mesh.positions.indices {
            let p = mesh.positions[index]
            #expect(abs(p.z - height(p.x, p.y)) <= 1e-12)
            #expect((mesh.normals[index] - (try normal(p.x, p.y))).length <= 1e-11)
            #expect(uNonclamped ? (2...3).contains(p.x) : (0...1).contains(p.x))
            #expect(vNonclamped ? (2...3).contains(p.y) : (0...1).contains(p.y))
        }
        let barycentrics = [(1.0 / 3, 1.0 / 3, 1.0 / 3), (0.5, 0.5, 0.0),
                            (0.5, 0.0, 0.5), (0.0, 0.5, 0.5), (0.5, 0.25, 0.25)]
        var measured = 0
        for triangle in 0..<(mesh.indices.count / 3) {
            let ids = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            let corners = ids.map { mesh.positions[$0] }
            let area = (corners[1] - corners[0]).cross(corners[2] - corners[0])
            #expect(area.z > 0)
            for edge in 0..<3 {
                #expect((corners[(edge + 1) % 3] - corners[edge]).length <= 0.25 * (1 + 1e-12))
            }
            for (a, b, c) in barycentrics {
                let p = Point3D(x: a * corners[0].x + b * corners[1].x + c * corners[2].x,
                                y: a * corners[0].y + b * corners[1].y + c * corners[2].y,
                                z: a * corners[0].z + b * corners[1].z + c * corners[2].z)
                #expect(abs(p.z - height(p.x, p.y)) <= options.linearTolerance * (1 + 1e-10))
                let expected = try normal(p.x, p.y)
                for id in ids {
                    #expect(atan2(mesh.normals[id].cross(expected).length,
                                  mesh.normals[id].dot(expected)) <= options.angularTolerance * (1 + 1e-10))
                }
                measured += 1
            }
        }
        #expect(measured > 0)
        #expect(model == original)
        try verifyProvenance(mesh, model: model)
    }

    private func verifyProvenance(_ mesh: Mesh, model: BRepModel) throws {
        let faceID = try #require(model.faces.keys.first)
        #expect(mesh.faceRuns == [Mesh.FaceRun(faceID: faceID, triangleCount: mesh.indices.count / 3)])
        #expect(Set(mesh.indices.map(Int.init)).count == mesh.positions.count)
    }

    /// The nonclamped quadratic basis on 2...3 has Greville coordinates 1.5,2.5,3.5
    /// and literal squared-coordinate coefficients 2,6,12; no library oracle is used.
    private static func quadraticSurface(uNonclamped: Bool, vNonclamped: Bool) -> BSplineSurface3D {
        let xs = uNonclamped ? [1.5, 2.5, 3.5] : [0, 1]
        let ys = vNonclamped ? [1.5, 2.5, 3.5] : [0, 1]
        let xHeights = uNonclamped ? [0.25, 0.75, 1.5] : [0, 0]
        let yHeights = vNonclamped ? [0.125, 0.375, 0.75] : [0, 0]
        return BSplineSurface3D(uDegree: uNonclamped ? 2 : 1, vDegree: vNonclamped ? 2 : 1,
            uKnots: uNonclamped ? [0, 1, 2, 3, 4, 5] : [0, 0, 1, 1],
            vKnots: vNonclamped ? [0, 1, 2, 3, 4, 5] : [0, 0, 1, 1],
            controlPoints: ys.indices.map { j in xs.indices.map { i in
                Point3D(x: xs[i], y: ys[j], z: xHeights[i] + yHeights[j])
            } })
    }

    private static func c0Surface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [1, 2, 2.5, 3, 4], vKnots: [0, 0, 1, 1], controlPoints: [
                [Point3D(x: 2, y: 0, z: 0), Point3D(x: 2.5, y: 0, z: 0.25), Point3D(x: 3, y: 0, z: 0)],
                [Point3D(x: 2, y: 1, z: 0), Point3D(x: 2.5, y: 1, z: 0.25), Point3D(x: 3, y: 1, z: 0)]])
    }

    private static func sheet(surface: BSplineSurface3D,
                              curves supplied: [SurfaceParameterCurve]? = nil) throws -> BRepModel {
        let u0 = surface.uKnots[surface.uDegree], u1 = surface.uKnots[surface.uControlPointCount]
        let v0 = surface.vKnots[surface.vDegree], v1 = surface.vKnots[surface.vControlPointCount]
        let curves = supplied ?? [
            .constantV(v: v0, uStart: u0, uEnd: u1), .constantU(u: u1, vStart: v0, vEnd: v1),
            .constantV(v: v1, uStart: u1, uEnd: u0), .constantU(u: u0, vStart: v1, vEnd: v0)]
        let support = Surface3D.bSpline(surface)
        let vertices = try curves.map { curve -> Vertex in
            let p = try curve.parameter(atNormalizedFraction: 0, tolerance: .standard)
            return Vertex(point: try support.point(u: p.u, v: p.v, tolerance: .standard))
        }
        var model = BRepModel(), coedges: [Coedge] = []
        for index in curves.indices {
            let curveID = CurveID()
            model.geometry.curves[curveID] = .surfaceLift(
                SurfaceLiftCurve3D(surface: support, parameterCurve: curves[index]))
            let edge = Edge(curveID: curveID, startVertexID: vertices[index].id,
                endVertexID: vertices[(index + 1) % vertices.count].id,
                trim: CurveTrim(startParameter: 0, endParameter: 1))
            model.edges[edge.id] = edge
            coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: curves[index]))
        }
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        let surfaceID = SurfaceID(), loop = Loop(coedges: coedges)
        let face = Face(surfaceID: surfaceID, loops: [loop.id]), shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.geometry.surfaces[surfaceID] = support
        model.loops[loop.id] = loop; model.faces[face.id] = face
        model.shells[shell.id] = shell; model.bodies[body.id] = body
        return model
    }
}
