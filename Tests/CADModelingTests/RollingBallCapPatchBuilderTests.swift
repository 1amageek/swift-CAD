import Testing
import CADCore
import CADGeometry
import CADModeling

@Suite("Rolling-ball cap boundary replacement")
struct RollingBallCapPatchBuilderTests {
    private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
    private let surface = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))

    private func edge(_ id: String, _ start: Point2D, _ end: Point2D) throws -> BRepSewingEdge {
        let parameters = SurfaceParameterCurve.affine(origin: start,
            direction: Point2D(x: end.x - start.x, y: end.y - start.y),
            startParameter: 0, endParameter: 1)
        let curve = Curve3D.surfaceLift(.init(surface: surface, parameterCurve: parameters))
        return BRepSewingEdge(stableID: id, curve: curve, startParameter: 0, endParameter: 1,
            startPoint: try curve.point(at: 0, tolerance: tolerance),
            endPoint: try curve.point(at: 1, tolerance: tolerance), surfaceParameterCurve: parameters)
    }

    private func square() throws -> BRepSewingFacePatch {
        let points = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0),
                      Point2D(x: 1, y: 1), Point2D(x: 0, y: 1)]
        return BRepSewingFacePatch(stableID: "cap", surface: surface, orientation: .forward,
            loops: [.init(stableID: "outer", role: .outer,
                edges: try points.indices.map { try edge("\($0)", points[$0], points[($0 + 1) % 4]) })])
    }

    @Test func replacesChainAndTrimsItsNeighbors() throws {
        let source = try square()
        let rail = try edge("contact", .init(x: 1, y: 0.8), .init(x: 0, y: 0.8))
        let result = try RollingBallCapPatchBuilder().build(source: source,
            replacing: ["2": rail], tolerance: tolerance)
        let edges = result.loops[0].edges
        #expect(edges.count == 4)
        #expect(edges[2].curve == rail.curve)
        #expect(edges[2].stableID == source.loops[0].edges[2].stableID)
        #expect(edges[2].stableID != rail.stableID)
        #expect(edges[1].endPoint == rail.startPoint)
        #expect(edges[3].startPoint == rail.endPoint)
        #expect(edges[0].curve == source.loops[0].edges[0].curve)
        #expect(source.loops[0].edges[1].endPoint != rail.startPoint)
        #expect(result.surface == source.surface)
        try result.validate(tolerance: tolerance)
    }

    @Test func cyclicChainAndOneRemainingEdgeRetainCorrectSegments() throws {
        let source = try square()
        let wrap = try [
            "3": edge("left", .init(x: 0.2, y: 1), .init(x: 0.2, y: 0.2)),
            "0": edge("bottom", .init(x: 0.2, y: 0.2), .init(x: 1, y: 0.2)),
        ]
        let wrapped = try RollingBallCapPatchBuilder().build(source: source, replacing: wrap, tolerance: tolerance)
        #expect(wrapped.loops[0].edges[2].endPoint == wrap["3"]?.startPoint)
        #expect(wrapped.loops[0].edges[1].startPoint == wrap["0"]?.endPoint)
        let three = try [
            "0": edge("bottom", .init(x: 0, y: 0.2), .init(x: 0.8, y: 0.2)),
            "1": edge("right", .init(x: 0.8, y: 0.2), .init(x: 0.8, y: 0.8)),
            "2": edge("top", .init(x: 0.8, y: 0.8), .init(x: 0, y: 0.8)),
        ]
        let trimmed = try RollingBallCapPatchBuilder().build(source: source, replacing: three, tolerance: tolerance)
        #expect(trimmed.loops[0].edges[3].startPoint == three["2"]?.endPoint)
        #expect(trimmed.loops[0].edges[3].endPoint == three["0"]?.startPoint)
        try trimmed.validate(tolerance: tolerance)
    }

    @Test func refusesMissingDisconnectedAndOffBoundaryContacts() throws {
        let source = try square()
        let rail = try edge("contact", .init(x: 1, y: 0.8), .init(x: 0, y: 0.8))
        let offBoundary = try edge("off-boundary", .init(x: 0.9, y: 0.8), .init(x: 0, y: 0.8))
        for replacements in [["missing": rail], ["0": rail, "2": rail], ["2": offBoundary]] {
            #expect(throws: KernelError.self) {
                _ = try RollingBallCapPatchBuilder().build(source: source,
                    replacing: replacements, tolerance: tolerance)
            }
        }
    }

    @Test func wholeLoopReplacementPreservesUntouchedHole() throws {
        let outer = try square()
        let holePoints = [Point2D(x: 0.4, y: 0.4), Point2D(x: 0.4, y: 0.6),
                          Point2D(x: 0.6, y: 0.6), Point2D(x: 0.6, y: 0.4)]
        let hole = BRepSewingLoop(stableID: "hole", role: .inner,
            edges: try holePoints.indices.map {
                try edge("hole:\($0)", holePoints[$0], holePoints[($0 + 1) % 4])
            })
        let source = BRepSewingFacePatch(stableID: outer.stableID, surface: surface,
            orientation: outer.orientation, loops: outer.loops + [hole])
        let inset = [Point2D(x: 0.2, y: 0.2), Point2D(x: 0.8, y: 0.2),
                     Point2D(x: 0.8, y: 0.8), Point2D(x: 0.2, y: 0.8)]
        var replacements: [String: BRepSewingEdge] = [:]
        for index in inset.indices {
            replacements["\(index)"] = try edge("inset:\(index)", inset[index], inset[(index + 1) % 4])
        }
        let result = try RollingBallCapPatchBuilder().build(source: source,
            replacing: replacements, tolerance: tolerance)
        #expect(result.loops.count == 2)
        #expect(result.loops[1].stableID == hole.stableID)
        #expect(result.loops[1].role == .inner)
        #expect(result.loops[1].edges.map(\.curve) == hole.edges.map(\.curve))
        #expect(result.loops[0].edges.map(\.stableID) == source.loops[0].edges.map(\.stableID))
        for index in inset.indices {
            #expect(result.loops[0].edges[index].curve == replacements["\(index)"]?.curve)
        }
        try result.validate(tolerance: tolerance)
    }

    @Test func reversedTrimDerivesAnOrientedPcurveFromTheLift() throws {
        let source = try square()
        let full = try edge("extended", .init(x: -0.25, y: 0.8), .init(x: 1.25, y: 0.8))
        let rail = BRepSewingEdge(stableID: "reverse-contact", curve: full.curve,
            startParameter: 5.0 / 6, endParameter: 1.0 / 6,
            startPoint: try surface.point(u: 1, v: 0.8, tolerance: tolerance),
            endPoint: try surface.point(u: 0, v: 0.8, tolerance: tolerance),
            surfaceParameterCurve: full.surfaceParameterCurve)
        let result = try RollingBallCapPatchBuilder().build(source: source,
            replacing: ["2": rail], tolerance: tolerance)
        let retained = result.loops[0].edges[2]
        #expect(retained.curve == rail.curve)
        #expect(retained.startParameter == rail.startParameter)
        #expect(retained.endParameter == rail.endParameter)
        let first = try retained.surfaceParameterCurve.startParameter(tolerance: tolerance)
        let last = try retained.surfaceParameterCurve.endParameter(tolerance: tolerance)
        #expect(abs(first.u - 1) <= tolerance.relative)
        #expect(abs(last.u) <= tolerance.relative)
        try result.validate(tolerance: tolerance)
    }
}
