import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADKernel

@Suite("Original graph-band public mesh composition")
struct OriginalGraphBandMeshTests {
    private let tolerance = ModelingTolerance.standard
    private var options: TessellationOptions {
        .init(linearTolerance: 1e-4, angularTolerance: 0.05, maxEdgeLength: 0.15)
    }

    @Test(.timeLimit(.minutes(2)))
    func nonconvexOriginalBandHasCompleteInteriorAndOneFaceRun() throws {
        let fixture = literalBand()
        let original = fixture.model
        let meshes = try MeshTessellator(tolerance: tolerance).tessellate(model: fixture.model, options: options)
        #expect(meshes.count == 1)
        let mesh = try #require(meshes[fixture.bodyID])
        try verify(mesh, faceID: fixture.faceID, crease: false, options: options)
        #expect(fixture.model == original)
    }

    @Test(.timeLimit(.minutes(2)))
    func originalC0BandKeepsCompatiblePositionsAndDistinctNormalOwners() throws {
        let fixture = literalBand(crease: true)
        let mesh = try #require(try MeshTessellator(tolerance: tolerance)
            .tessellate(model: fixture.model, options: options)[fixture.bodyID])
        try verify(mesh, faceID: fixture.faceID, crease: true, options: options)
        let atCrease = mesh.positions.indices.filter { abs(mesh.positions[$0].x - 0.5) < 1e-12 }
        #expect(atCrease.isEmpty == false)
        var matchedOwners = false
        for a in atCrease {
            for b in atCrease where a < b && mesh.positions[a] == mesh.positions[b] {
                if abs(mesh.normals[a].x - mesh.normals[b].x) > 0.2 { matchedOwners = true }
            }
        }
        #expect(matchedOwners)
    }

    @Test(.timeLimit(.minutes(2)))
    func looseCallerAngleKeepsTheStricterProofAllocation() throws {
        let fixture = literalBand()
        var loose = options
        loose.angularTolerance = 4
        let originalOptions = loose
        let mesh = try #require(try MeshTessellator(tolerance: tolerance)
            .tessellate(model: fixture.model, options: loose)[fixture.bodyID])
        try verify(mesh, faceID: fixture.faceID, crease: false, options: loose)
        #expect(loose == originalOptions)
    }

    @Test(.timeLimit(.minutes(2)))
    func callerStorageRefusalPreservesTheOriginalModel() throws {
        let fixture = literalBand()
        let original = fixture.model
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 1
        do {
            _ = try MeshTessellator(tolerance: tolerance, limits: limits)
                .tessellate(model: fixture.model, options: options)
            Issue.record("A complete graph-band mesh exceeded its caller vertex ceiling.")
        } catch let error as TessellationError {
            guard case let .resourceExhausted(resource, requested, limit) = error else {
                Issue.record("Expected a storage resource refusal, received \(error).")
                return
            }
            #expect(resource == .vertexCount && requested > limit && limit == 1)
        }
        #expect(fixture.model == original)
    }

    @Test(.timeLimit(.minutes(2)))
    func geometricCoincidenceCannotReplaceTheDirectedVertexIDCycle() throws {
        let fixture = literalBand()
        var model = fixture.model
        let originalEdge = try #require(model.edges[fixture.edgeIDs[0]])
        let point = try #require(model.vertices[originalEdge.endVertexID]).point
        let foreign = Vertex(point: point)
        model.vertices[foreign.id] = foreign
        var disconnected = originalEdge
        disconnected.endVertexID = foreign.id
        model.edges[disconnected.id] = disconnected
        do {
            _ = try MeshTessellator(tolerance: tolerance).tessellate(model: model, options: options)
            Issue.record("Coincident points silently replaced disconnected original vertex identities.")
        } catch let error as TopologyError {
            #expect(error == .openLoop(fixture.loopID))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func invalidDirectedSpatialTrimCannotPublishAFallbackMesh() throws {
        let fixture = literalBand()
        var model = fixture.model
        var edge = try #require(model.edges[fixture.edgeIDs[2]])
        edge.trim = CurveTrim(startParameter: 1, endParameter: 0)
        model.edges[edge.id] = edge
        do {
            _ = try MeshTessellator(tolerance: tolerance).tessellate(model: model, options: options)
            Issue.record("A foreign directed spatial trim produced a mesh.")
        } catch let error as TopologyError {
            #expect(error == .invalidTrim(edge.id))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func cancelledOriginalMeshCompositionPublishesNoPartialResult() async throws {
        let fixture = literalBand()
        let original = fixture.model
        let task = Task {
            while Task.isCancelled == false { await Task.yield() }
            return try MeshTessellator(tolerance: tolerance).tessellate(model: fixture.model, options: options)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(fixture.model == original)
    }

    private struct Fixture: Sendable {
        let model: BRepModel
        let bodyID: BodyID
        let faceID: FaceID
        let loopID: LoopID
        let edgeIDs: [EdgeID]
    }

    private func literalBand(crease: Bool = false) -> Fixture {
        // L(u)=-u+4u²-6u³+3u⁴, H(u)=u-u²; the projected area is 7/30.
        // The inward lower dent makes this band nonconvex. Native V includes all negative L.
        let xs = crease ? [0.0, 1.0/6, 1.0/3, 0.5, 2.0/3, 5.0/6, 1.0]
            : [0.0, 1.0/3, 2.0/3, 1.0]
        let support = BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: crease ? [0,0,0,0,0.5,0.5,0.5,1,1,1,1] : [0,0,0,0,1,1,1,1],
            vKnots: [-1,-1,1,1], controlPoints: [-1.0, 1.0].map { v in
                xs.map { Point3D(x: $0, y: v, z: crease ? max(0, ($0 - 0.5) / 4) : 0) }
            })
        let lowerLeft = [Point2D(x: 0, y: 0), .init(x: 0.125, y: -1.0/8),
            .init(x: 0.25, y: -1.0/12), .init(x: 0.375, y: -1.0/16), .init(x: 0.5, y: -1.0/16)]
        let lowerRight = lowerLeft.reversed().map { Point2D(x: 1 - $0.x, y: $0.y) }
        let upperLeft = [Point2D(x: 0, y: 0), .init(x: 0.25, y: 0.25), .init(x: 0.5, y: 0.25)]
        let upperRight = upperLeft.reversed().map { Point2D(x: 1 - $0.x, y: $0.y) }
        // Spatial edges are stored in increasing U. The upper two uses reverse
        // the spatial trims, while their retained pcurves already follow each use.
        let stored = [lowerLeft, lowerRight, upperRight, upperLeft]
        let usePoints = [lowerLeft, lowerRight, Array(upperRight.reversed()), Array(upperLeft.reversed())]
        let vertices = [Point2D(x: 0, y: 0), .init(x: 0.5, y: -1.0/16),
            .init(x: 1, y: 0), .init(x: 0.5, y: 0.25)].map {
                Vertex(point: .init(x: $0.x, y: $0.y, z: crease ? max(0, ($0.x - 0.5) / 4) : 0))
            }
        var model = BRepModel()
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        var coedges: [Coedge] = []
        var edgeIDs: [EdgeID] = []
        for index in 0..<4 {
            let degree = stored[index].count - 1
            let knots = Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
            let curveID = CurveID()
            model.geometry.curves[curveID] = .bSpline(BSplineCurve3D(degree: degree, knots: knots,
                controlPoints: stored[index].map {
                    Point3D(x: $0.x, y: $0.y, z: crease ? max(0, ($0.x - 0.5) / 4) : 0)
                }))
            let reverse = index >= 2
            let edge = Edge(curveID: curveID,
                startVertexID: vertices[reverse ? (index + 1) % 4 : index].id,
                endVertexID: vertices[reverse ? index : (index + 1) % 4].id,
                trim: .init(startParameter: 0, endParameter: 1))
            model.edges[edge.id] = edge
            edgeIDs.append(edge.id)
            coedges.append(Coedge(edgeID: edge.id, orientation: reverse ? .reversed : .forward,
                surfaceParameterCurve: .bSpline(BSplineCurve2D(degree: degree, knots: knots, controlPoints: usePoints[index]))))
        }
        let surfaceID = SurfaceID()
        model.geometry.surfaces[surfaceID] = .bSpline(support)
        let loop = Loop(coedges: coedges)
        let face = Face(surfaceID: surfaceID, loops: [loop.id])
        let shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.loops[loop.id] = loop
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return Fixture(model: model, bodyID: body.id, faceID: face.id, loopID: loop.id, edgeIDs: edgeIDs)
    }

    private func lower(_ u: Double) -> Double { -u + 4*u*u - 6*u*u*u + 3*u*u*u*u }
    private func upper(_ u: Double) -> Double { u - u*u }

    private func verify(_ mesh: Mesh, faceID: FaceID, crease: Bool, options: TessellationOptions) throws {
        try mesh.validate(tolerance: tolerance)
        #expect(mesh.indices.isEmpty == false && mesh.indices.count % 3 == 0)
        #expect(mesh.faceRuns == [.init(faceID: faceID, triangleCount: mesh.indices.count / 3)])
        var projectedArea = 0.0
        var maximumEdge = 0.0
        var wholePositionError = 0.0
        var wholeAngleError = 0.0
        var vertexIDs: [Point3D: Int] = [:]
        var edgeCounts: [[Int]: Int] = [:]
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0..<3).map { Int(mesh.indices[triangle + $0]) }
            let points = ids.map { mesh.positions[$0] }
            let xs = points.map(\.x)
            let minX = try #require(xs.min()), maxX = try #require(xs.max())
            if crease { #expect(!(minX < 0.5 - 1e-12 && maxX > 0.5 + 1e-12)) }
            let right = crease && minX >= 0.5 - 1e-12 && maxX > 0.5 + 1e-12
            let normal = try Vector3D(x: right ? -0.25 : 0, y: 0, z: 1).normalized(tolerance: 1e-300)
            let twiceArea = cross(points[0], points[1], points[2])
            #expect(twiceArea > 0)
            projectedArea += twiceArea / 2
            var vertexViolation = 0.0, planeError = 0.0
            for (index, point) in zip(ids, points) {
                #expect(point.x >= -options.linearTolerance && point.x <= 1 + options.linearTolerance)
                vertexViolation = max(vertexViolation, lower(point.x) - point.y, point.y - upper(point.x))
                planeError = max(planeError, abs(point.z - (right ? (point.x - 0.5) / 4 : 0)))
                let n = mesh.normals[index]
                wholeAngleError = max(wholeAngleError, atan2(normal.cross(n).length, normal.dot(n)))
                if vertexIDs[point] == nil { vertexIDs[point] = vertexIDs.count }
            }
            // |L''|<=8 and |H''|=2 on [0,1]. For every barycentric point,
            // variance(x)<=width²/4, so interpolation adds at most width².
            // The selected support is affine on each side; its vertex plane
            // error bounds the entire facet, not just sampled barycentrics.
            wholePositionError = max(wholePositionError, max(0, vertexViolation) + pow(maxX - minX, 2) + planeError)
            for edge in 0..<3 {
                let a = points[edge], b = points[(edge + 1) % 3]
                maximumEdge = max(maximumEdge, (a - b).length)
                let ia = try #require(vertexIDs[a]), ib = try #require(vertexIDs[b])
                edgeCounts[[min(ia, ib), max(ia, ib)], default: 0] += 1
            }
        }
        #expect(wholePositionError <= options.linearTolerance)
        #expect(wholeAngleError <= min(options.angularTolerance, Double.pi))
        #expect(maximumEdge <= (try #require(options.maxEdgeLength)))
        // Original boundary length is below six. A distance-L complete boundary
        // has a conservative six-L plus pi-L² projected area allowance.
        #expect(abs(projectedArea - 7.0/30) <= 6*options.linearTolerance + Double.pi*pow(options.linearTolerance, 2))
        #expect(edgeCounts.values.allSatisfy { $0 == 1 || $0 == 2 })
        #expect(vertexIDs.count - edgeCounts.count + mesh.indices.count / 3 == 1)
        var boundary: [Int: Set<Int>] = [:]
        for (edge, count) in edgeCounts where count == 1 {
            boundary[edge[0], default: []].insert(edge[1])
            boundary[edge[1], default: []].insert(edge[0])
        }
        #expect(boundary.isEmpty == false && boundary.values.allSatisfy { $0.count == 2 })
        if let first = boundary.keys.first {
            var visited: Set<Int> = [], pending = [first]
            while let id = pending.popLast() {
                if visited.insert(id).inserted { pending.append(contentsOf: boundary[id] ?? []) }
            }
            #expect(visited.count == boundary.count)
        }
        for u in [0.05, 0.125, 0.25, 0.4, 0.5, 0.6, 0.75, 0.875, 0.95] {
            for w in [0.02, 0.25, 0.5, 0.75, 0.98] {
                #expect(contains(mesh, x: u, y: lower(u) + w * (upper(u) - lower(u))))
            }
        }
        #expect(contains(mesh, x: 0.25, y: -0.07) && contains(mesh, x: 0.75, y: -0.07))
        #expect(contains(mesh, x: 0.5, y: -0.07) == false)
    }

    private func cross(_ a: Point3D, _ b: Point3D, _ c: Point3D) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private func contains(_ mesh: Mesh, x: Double, y: Double) -> Bool {
        let point = Point3D(x: x, y: y, z: 0)
        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[start])]
            let b = mesh.positions[Int(mesh.indices[start + 1])]
            let c = mesh.positions[Int(mesh.indices[start + 2])]
            if cross(a, b, point) >= -1e-14 && cross(b, c, point) >= -1e-14 && cross(c, a, point) >= -1e-14 { return true }
        }
        return false
    }
}
