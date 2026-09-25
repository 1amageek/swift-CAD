import Testing
import CADCore
import CADTopology

@Suite("Open boundary loop resolution")
struct OpenBoundaryLoopResolverTests {
    @Test(.timeLimit(.minutes(1)))
    func discoversClosedSingleEdgesAndTwoEdgeCycles() throws {
        let fixture = model(loops: [
            (vertices: [0], role: .outer),
            (vertices: [1, 2], role: .inner),
        ])
        let resolver = OpenBoundaryLoopResolver()
        let loops = resolver.loops(in: fixture.body, model: fixture.model)
        #expect(loops.map(\.traversals.count).sorted() == [1, 2])
        for boundary in loops {
            let seed = try #require(boundary.traversals.first?.edgeID)
            #expect(resolver.loop(startingAt: seed, in: fixture.body, model: fixture.model) == boundary)
            #expect(resolver.isFillableSurfaceBoundary(boundary, in: fixture.body, model: fixture.model)
                    == (boundary.traversals.count == 2))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedCoedgeUseIsNotAnOpenBoundaryEvenOnOneFace() throws {
        let fixture = model(loops: [(vertices: [0, 1, 2], role: .outer)])
        var brep = fixture.model
        let loopID = try #require(brep.loops.keys.first)
        var loop = try #require(brep.loops[loopID])
        loop.coedges.append(try #require(loop.coedges.first))
        brep.loops[loopID] = loop
        #expect(OpenBoundaryLoopResolver().loops(in: fixture.body, model: brep).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func discoversDisjointCyclesAndSeedsTraversalInStoredDirection() throws {
        let fixture = model(
            loops: [
                (vertices: [0, 1, 2, 3], role: LoopRole.outer),
                (vertices: [4, 5, 6, 7, 8], role: LoopRole.inner),
                (vertices: [9, 10, 11], role: LoopRole.inner),
            ]
        )
        let resolver = OpenBoundaryLoopResolver()

        let loops = resolver.loops(in: fixture.body, model: fixture.model)

        #expect(loops.map(\.traversals.count).sorted() == [3, 4, 5])
        for loop in loops {
            let seed = loop.traversals[0].edgeID
            let seededLoop = try #require(resolver.loop(
                startingAt: seed,
                in: fixture.body,
                model: fixture.model
            ))
            #expect(loop == seededLoop)
        }

        let seed = loops[1].traversals[2].edgeID
        let seeded = try #require(resolver.loop(
            startingAt: seed,
            in: fixture.body,
            model: fixture.model
        ))
        #expect(seeded.traversals.first?.edgeID == seed)
        #expect(seeded.traversals.first?.followsStoredDirection == true)
        for index in seeded.traversals.indices {
            let current = seeded.traversals[index]
            let next = seeded.traversals[(index + 1) % seeded.traversals.count]
            let currentEdge = try #require(fixture.model.edges[current.edgeID])
            let nextEdge = try #require(fixture.model.edges[next.edgeID])
            let currentEnd = current.followsStoredDirection
                ? currentEdge.endVertexID : currentEdge.startVertexID
            let nextStart = next.followsStoredDirection
                ? nextEdge.startVertexID : nextEdge.endVertexID
            #expect(currentEnd == nextStart)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func excludesBranchedAndOpenComponentsWithoutHidingValidLoops() throws {
        let fixture = model(
            loops: [
                (vertices: [0, 1, 2, 3], role: LoopRole.outer),
                (vertices: [4, 5, 6], role: LoopRole.inner),
            ],
            branch: (center: 7, endpoints: [8, 9, 10]),
            openChains: [[11, 12, 13]]
        )
        let resolver = OpenBoundaryLoopResolver()

        let loops = resolver.loops(in: fixture.body, model: fixture.model)

        #expect(loops.map(\.traversals.count).sorted() == [3, 4])
        #expect(resolver.loop(
            startingAt: fixture.branchSeed,
            in: fixture.body,
            model: fixture.model
        ) == nil)
        #expect(resolver.loop(
            startingAt: fixture.openChainSeed,
            in: fixture.body,
            model: fixture.model
        ) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func onlyInnerLoopCanFillTheOuterBoundaryOfASingleFace() throws {
        let fixture = model(loops: [
            (vertices: [0, 1, 2, 3], role: .outer),
            (vertices: [4, 5, 6, 7], role: .inner),
        ])
        let resolver = OpenBoundaryLoopResolver()
        let loops = resolver.loops(in: fixture.body, model: fixture.model)

        #expect(loops.count == 2)
        #expect(loops.filter {
            resolver.isFillableSurfaceBoundary($0, in: fixture.body, model: fixture.model)
        }.map(\.traversals.count) == [4])
        let inner = try #require(loops.first {
            resolver.isFillableSurfaceBoundary($0, in: fixture.body, model: fixture.model)
        })
        let outer = try #require(loops.first { $0 != inner })
        #expect(resolver.isFillableSurfaceBoundary(inner, in: fixture.body, model: fixture.model))
        #expect(resolver.isFillableSurfaceBoundary(outer, in: fixture.body, model: fixture.model) == false)
    }

    private func model(
        loops loopDefinitions: [(vertices: [Int], role: LoopRole)],
        branch: (center: Int, endpoints: [Int])? = nil,
        openChains: [[Int]] = []
    ) -> Fixture {
        let bodyID = BodyID()
        let shellID = ShellID()
        let faceID = FaceID()
        var edges: [EdgeID: Edge] = [:]
        var boundaryLoops: [LoopID: Loop] = [:]
        var allLoopIDs: [LoopID] = []
        var vertexIDs: [Int: VertexID] = [:]
        var edgeIDs: [[EdgeID]] = []

        func vertex(_ index: Int) -> VertexID {
            if let id = vertexIDs[index] { return id }
            let id = VertexID()
            vertexIDs[index] = id
            return id
        }

        for definition in loopDefinitions {
            let loopID = LoopID()
            let ids = definition.vertices.indices.map { _ in EdgeID() }
            for index in definition.vertices.indices {
                let next = (index + 1) % definition.vertices.count
                let edge = Edge(
                    id: ids[index],
                    curveID: CurveID(),
                    startVertexID: vertex(definition.vertices[index]),
                    endVertexID: vertex(definition.vertices[next])
                )
                edges[edge.id] = edge
            }
            boundaryLoops[loopID] = Loop(
                id: loopID,
                role: definition.role,
                coedges: ids.map { Coedge(edgeID: $0) }
            )
            allLoopIDs.append(loopID)
            edgeIDs.append(ids)
        }

        var branchSeed = edgeIDs.first?.first ?? EdgeID()
        if let branch {
            let loopID = LoopID()
            let ids = branch.endpoints.map { _ in EdgeID() }
            for (edgeID, endpoint) in zip(ids, branch.endpoints) {
                let edge = Edge(
                    id: edgeID,
                    curveID: CurveID(),
                    startVertexID: vertex(branch.center),
                    endVertexID: vertex(endpoint)
                )
                edges[edgeID] = edge
            }
            boundaryLoops[loopID] = Loop(
                id: loopID,
                role: .inner,
                coedges: ids.map { Coedge(edgeID: $0) }
            )
            allLoopIDs.append(loopID)
            branchSeed = ids[0]
        }

        var openChainEdgeIDs: [EdgeID] = []
        for chain in openChains {
            let ids = (0..<(chain.count - 1)).map { _ in EdgeID() }
            for index in ids.indices {
                let edge = Edge(
                    id: ids[index],
                    curveID: CurveID(),
                    startVertexID: vertex(chain[index]),
                    endVertexID: vertex(chain[index + 1])
                )
                edges[edge.id] = edge
            }
            let loopID = LoopID()
            boundaryLoops[loopID] = Loop(
                id: loopID,
                role: .inner,
                coedges: ids.map { Coedge(edgeID: $0) }
            )
            allLoopIDs.append(loopID)
            if openChainEdgeIDs.isEmpty { openChainEdgeIDs = ids }
        }

        let body = Body(id: bodyID, sheetShellIDs: [shellID])
        let shell = Shell(id: shellID, faceIDs: [faceID])
        let face = Face(id: faceID, surfaceID: SurfaceID(), loops: allLoopIDs)
        let model = BRepModel(
            bodies: [bodyID: body],
            shells: [shellID: shell],
            faces: [faceID: face],
            loops: boundaryLoops,
            edges: edges
        )
        return Fixture(
            body: body,
            model: model,
            branchSeed: branchSeed,
            openChainSeed: openChainEdgeIDs.first ?? branchSeed
        )
    }

    private struct Fixture {
        let body: Body
        let model: BRepModel
        let branchSeed: EdgeID
        let openChainSeed: EdgeID
    }
}
