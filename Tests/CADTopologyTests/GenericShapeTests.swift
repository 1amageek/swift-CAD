import CADCore
import CADGeometry
import Synchronization
import Testing
import CADTopology

@Suite("Common dimensional Shape operations")
struct GenericShapeTests {
    private let operation: any ShapeOperating = DefaultShapeOperator()

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test(.timeLimit(.minutes(1)))
    func liveProviderIsCapturedOnceForEveryCommonOperation() throws {
        let first = Vertex(point: .origin)
        let second = Vertex(point: Point3D(x: 1, y: 2, z: 3))
        let provider = ChangingShapeProvider(first: first, second: second)

        let firstResult = try operation.extract(provider, tolerance: .standard)
        #expect(provider.acquisitionCount == 1)
        #expect(firstResult.root == .vertex(first.id))
        #expect(firstResult.model.vertices[first.id] == first)
        #expect(firstResult.model.vertices[second.id] == nil)

        let secondResult = try operation.extract(provider, tolerance: .standard)
        #expect(provider.acquisitionCount == 2)
        #expect(secondResult.root == .vertex(second.id))
        #expect(secondResult.model.vertices[second.id] == second)
        #expect(secondResult.model.vertices[first.id] == nil)

        try operation.validate(provider, tolerance: .standard)
        #expect(provider.acquisitionCount == 3)
        #expect(try operation.subshapes(of: provider, tolerance: .standard) == [.vertex(second.id)])
        #expect(provider.acquisitionCount == 4)

        let translation = RigidTransform3D.translated(by: Vector3D(x: 4, y: 5, z: 6))
        let moved = try operation.transformed(provider, by: translation, tolerance: .standard)
        #expect(provider.acquisitionCount == 5)
        #expect(moved.root == .vertex(first.id))
        #expect(moved.model.vertices[first.id]?.point == translation.applying(to: first.point))
        #expect(moved.model.vertices[second.id] == nil)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    private final class ChangingShapeProvider: ShapeRepresenting {
        private struct State {
            let firstRoot: ShapeReference
            let secondRoot: ShapeReference
            let model: BRepModel
            var acquisitions = 0
        }

        private let state: Mutex<State>

        init(first: Vertex, second: Vertex) {
            state = Mutex(State(firstRoot: .vertex(first.id), secondRoot: .vertex(second.id),
                                model: BRepModel(vertices: [first.id: first, second.id: second])))
        }

        var acquisitionCount: Int {
            state.withLock { $0.acquisitions }
        }

        func shapeSnapshot() -> Shape {
            state.withLock { value in
                let root = value.acquisitions.isMultiple(of: 2) ? value.firstRoot : value.secondRoot
                value.acquisitions += 1
                return Shape(root: root, model: value.model)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func everyDimensionUsesTheSamePublicOperations() throws {
        let model = try tetrahedron()
        let bodyID = try #require(model.bodies.keys.first)
        let shellID = try #require(model.shells.keys.first)
        let faceID = try #require(model.faces.keys.sorted().first)
        let loopID = try #require(model.faces[faceID]?.loops.first)
        let loop = try #require(model.loops[loopID])
        let wire = ShapeWire(edges: loop.coedges.prefix(2).map {
            ShapeEdgeUse(edgeID: $0.edgeID, orientation: $0.orientation)
        })
        let edgeID = try #require(wire.edges.first?.edgeID)
        let vertexID = try #require(model.edges[edgeID]?.startVertexID)
        let roots: [ShapeReference] = [.vertex(vertexID), .edge(edgeID), .wire(wire),
                                      .face(faceID), .shell(shellID), .solid(bodyID)]
        for root in roots {
            let input: any ShapeRepresenting = Shape(root: root, model: model)
            try operation.validate(input, tolerance: .standard)
            let extracted = try operation.extract(input, tolerance: .standard)
            #expect(extracted.root == root)
            #expect(try operation.subshapes(of: extracted, tolerance: .standard).contains(root))
            let transform = RigidTransform3D.translated(by: Vector3D(x: 2, y: -3, z: 4))
            let moved = try operation.transformed(input, by: transform, tolerance: .standard)
            #expect(moved.root == root)
            #expect(Set(moved.model.vertices.keys) == Set(extracted.model.vertices.keys))
            for (id, vertex) in extracted.model.vertices {
                #expect(moved.model.vertices[id]?.point == transform.applying(to: vertex.point))
            }
        }
        #expect(abs(try model.volume(tolerance: .standard) - 1.0 / 6.0) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func openAndClosedWiresPreserveOrderedDirection() throws {
        let model = try tetrahedron()
        let loop = try #require(model.loops.values.first)
        let edges = loop.coedges.map { ShapeEdgeUse(edgeID: $0.edgeID, orientation: $0.orientation) }
        let open = ShapeWire(edges: Array(edges.prefix(2)))
        let closed = ShapeWire(edges: edges)
        let reversed = ShapeWire(edges: edges.reversed().map {
            ShapeEdgeUse(edgeID: $0.edgeID, orientation: $0.orientation == .forward ? .reversed : .forward)
        })
        for wire in [open, closed, reversed] {
            let result = try operation.extract(Shape(root: .wire(wire), model: model), tolerance: .standard)
            #expect(result.root == .wire(wire))
            #expect(result.model.edges.count == wire.edges.count)
            #expect(result.model.faces.isEmpty)
            #expect(result.model.bodies.isEmpty)
        }
        #expect(throws: KernelError.self) {
            try operation.validate(Shape(root: .wire(ShapeWire(edges: [edges[0], edges[0]])), model: model), tolerance: .standard)
        }
        #expect(throws: KernelError.self) {
            try operation.validate(Shape(root: .wire(ShapeWire(edges: [])), model: model), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedHeterogeneousCompoundPreservesRootsAndDeduplicatesTopology() throws {
        let model = try tetrahedron()
        let bodyID = try #require(model.bodies.keys.first)
        let vertexID = try #require(model.vertices.keys.first)
        let faceID = try #require(model.faces.keys.first)
        let root = ShapeReference.compound([.vertex(vertexID), .compound([.face(faceID), .solid(bodyID)]), .solid(bodyID)])
        let shape = Shape(root: root, model: model)
        let result = try operation.extract(shape, tolerance: .standard)
        #expect(result.root == root)
        #expect(result.model == model)
        let subshapes = try operation.subshapes(of: result, tolerance: .standard)
        #expect(subshapes.filter { $0 == .solid(bodyID) }.count == 1)
        #expect(subshapes.filter { $0 == .vertex(vertexID) }.count == 1)
        let empty = try operation.extract(Shape(root: .compound([]), model: model), tolerance: .standard)
        #expect(empty.model == BRepModel())
        #expect(try operation.subshapes(of: empty, tolerance: .standard).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func extractionValidatesSelectedClosureAndPreservesBodyOwnership() throws {
        var model = try tetrahedron()
        let vertexID = try #require(model.vertices.keys.first)
        let unrelated = Vertex(point: Point3D(x: .nan, y: 0, z: 0))
        model.vertices[unrelated.id] = unrelated
        let extracted = try operation.extract(Shape(root: .vertex(vertexID), model: model), tolerance: .standard)
        #expect(extracted.model.vertices.count == 1)
        #expect(extracted.model.vertices[vertexID] == model.vertices[vertexID])
        #expect(model.vertices[unrelated.id] != nil)
        #expect(throws: TopologyError.self) {
            try extracted.model.validate(tolerance: .standard)
        }
        #expect(throws: TopologyError.self) {
            try operation.extract(Shape(root: .edge(EdgeID()), model: model), tolerance: .standard)
        }
        let bodyID = try #require(model.bodies.keys.first)
        let body = try #require(model.bodies[bodyID])
        model.bodies[bodyID] = Body(id: bodyID, sheetShellIDs: body.shellIDs)
        #expect(throws: TopologyError.self) {
            try operation.extract(Shape(root: .solid(bodyID), model: model), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedEndpointAndFacePcurveFailBeforeResult() throws {
        var model = try tetrahedron()
        let edgeID = try #require(model.edges.keys.first)
        let edge = try #require(model.edges[edgeID])
        let vertex = try #require(model.vertices[edge.endVertexID])
        model.vertices[vertex.id] = Vertex(id: vertex.id, point: vertex.point + Vector3D(x: 0.1, y: 0.2, z: 0.3))
        #expect(throws: TopologyError.self) {
            try operation.extract(Shape(root: .edge(edgeID), model: model), tolerance: .standard)
        }
        model = try tetrahedron()
        let faceID = try #require(model.faces.keys.first)
        let loopID = try #require(model.faces[faceID]?.loops.first)
        var loop = try #require(model.loops[loopID])
        loop.coedges[0].surfaceParameterCurve = .constantU(u: 100, vStart: 0, vEnd: 1)
        model.loops[loopID] = loop
        #expect(throws: (any Error).self) {
            try operation.extract(Shape(root: .face(faceID), model: model), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rotationAndReflectionTransportFaceChartsAndMaterialVolume() throws {
        let model = try tetrahedron()
        let bodyID = try #require(model.bodies.keys.first)
        let source = Shape(root: .solid(bodyID), model: model)
        let transforms = [
            try RigidTransform3D.rotated(around: .origin, direction: Vector3D(x: 1, y: 2, z: 3), angle: 0.73, tolerance: .standard),
            try RigidTransform3D.mirrored(across: Point3D(x: 2, y: 0, z: 0), normal: Vector3D(x: 1, y: 2, z: 3), tolerance: .standard),
        ]
        for transform in transforms {
            let output = try operation.transformed(source, by: transform, tolerance: .standard)
            #expect(abs(try output.model.volume(tolerance: .standard) - 1.0 / 6.0) < 1e-10)
            for (id, face) in model.faces {
                let oldSurface = try #require(model.geometry.surfaces[face.surfaceID])
                let newSurface = try #require(output.model.geometry.surfaces[face.surfaceID])
                let outputFace = try #require(output.model.faces[id])
                #expect(outputFace.id == face.id)
                for loopID in face.loops {
                    let oldLoop = try #require(model.loops[loopID])
                    let newLoop = try #require(output.model.loops[loopID])
                    for index in oldLoop.coedges.indices {
                        let oldCurve = try #require(oldLoop.coedges[index].surfaceParameterCurve)
                        let newCurve = try #require(newLoop.coedges[index].surfaceParameterCurve)
                        for fraction in [0.0, 0.37, 1.0] {
                            let oldParameter = try oldCurve.parameter(atNormalizedFraction: fraction, tolerance: .standard)
                            let newParameter = try newCurve.parameter(atNormalizedFraction: fraction, tolerance: .standard)
                            let oldPoint = try oldSurface.point(u: oldParameter.u, v: oldParameter.v, tolerance: .standard)
                            let newPoint = try newSurface.point(u: newParameter.u, v: newParameter.v, tolerance: .standard)
                            #expect(newPoint.isApproximatelyEqual(to: transform.applying(to: oldPoint), tolerance: 1e-9))
                        }
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func standaloneCurvedEdgePreservesItsParameterizationUnderRotation() throws {
        let curve = Curve3D.circle(Circle3D(center: .origin, normal: .unitZ, radius: 2))
        let start = Vertex(point: try curve.point(at: 0, tolerance: .standard))
        let end = Vertex(point: try curve.point(at: .pi / 2, tolerance: .standard))
        let curveID = CurveID()
        let edge = Edge(curveID: curveID, startVertexID: start.id, endVertexID: end.id,
                        trim: CurveTrim(startParameter: 0, endParameter: .pi / 2))
        let model = BRepModel(geometry: GeometryStore(curves: [curveID: curve]), edges: [edge.id: edge],
                              vertices: [start.id: start, end.id: end])
        let transform = try RigidTransform3D.rotated(around: .origin, direction: .unitX, angle: 0.8, tolerance: .standard)
        let output = try operation.transformed(Shape(root: .edge(edge.id), model: model), by: transform, tolerance: .standard)
        let resultCurve = try #require(output.model.geometry.curves[curveID])
        for parameter in [0.0, 0.4, .pi / 2] {
            let expected = transform.applying(to: try curve.point(at: parameter, tolerance: .standard))
            #expect(try resultCurve.point(at: parameter, tolerance: .standard).isApproximatelyEqual(to: expected, tolerance: 1e-10))
        }
        #expect(output.model.edges[edge.id]?.trim == edge.trim)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationPropagatesBeforeTraversal() async throws {
        let model = try tetrahedron()
        let root = ShapeReference.solid(try #require(model.bodies.keys.first))
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in stream { break }
            return try operation.extract(Shape(root: root, model: model), tolerance: .standard)
        }
        task.cancel()
        continuation.yield()
        continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func tetrahedron() throws -> BRepModel {
        let tolerance = ModelingTolerance.standard
        let points = [Point3D.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0), Point3D(x: 0, y: 0, z: 1)]
        let vertices = points.map { Vertex(point: $0) }
        var model = BRepModel(vertices: Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) }))
        var edgeIDs: [String: EdgeID] = [:]
        var faceIDs: [FaceID] = []
        for indices in [[0, 2, 1], [0, 1, 3], [0, 3, 2], [1, 2, 3]] {
            let a = points[indices[0]], b = points[indices[1]], c = points[indices[2]]
            let normal = try (b - a).cross(c - a).normalized(tolerance: tolerance.distance)
            let surface = Surface3D.plane(Plane3D(origin: a, normal: normal))
            let surfaceID = SurfaceID()
            model.geometry.surfaces[surfaceID] = surface
            var uses: [Coedge] = []
            for index in indices.indices {
                let first = indices[index], last = indices[(index + 1) % indices.count]
                let key = "\(min(first, last)):\(max(first, last))"
                let edgeID: EdgeID
                let orientation: Orientation
                if let existingID = edgeIDs[key], let existing = model.edges[existingID] {
                    edgeID = existingID
                    orientation = existing.startVertexID == vertices[first].id ? .forward : .reversed
                } else {
                    let curveID = CurveID()
                    let direction = try (points[last] - points[first]).normalized(tolerance: tolerance.distance)
                    model.geometry.curves[curveID] = .line(Line3D(origin: points[first], direction: direction))
                    let edge = Edge(curveID: curveID, startVertexID: vertices[first].id, endVertexID: vertices[last].id,
                                    trim: CurveTrim(startParameter: 0, endParameter: (points[last] - points[first]).length))
                    edgeID = edge.id
                    model.edges[edgeID] = edge
                    edgeIDs[key] = edgeID
                    orientation = .forward
                }
                let start = try surface.parameterProjection(of: points[first], tolerance: tolerance)
                let end = try surface.parameterProjection(of: points[last], tolerance: tolerance)
                uses.append(Coedge(edgeID: edgeID, orientation: orientation,
                                   surfaceParameterCurve: .polyline([SurfaceParameter(u: start.u, v: start.v), SurfaceParameter(u: end.u, v: end.v)])))
            }
            let loop = Loop(coedges: uses)
            let face = Face(surfaceID: surfaceID, loops: [loop.id])
            model.loops[loop.id] = loop
            model.faces[face.id] = face
            faceIDs.append(face.id)
        }
        let shell = Shell(faceIDs: faceIDs)
        let body = Body(solidComponents: [SolidShellComponent(outerShellID: shell.id)])
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return model
    }
}
