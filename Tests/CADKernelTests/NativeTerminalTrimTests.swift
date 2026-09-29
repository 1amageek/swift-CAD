import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
@testable import CADKernel

@Suite("Native terminal trim", .timeLimit(.minutes(2)))
struct NativeTerminalTrimTests {
    struct Fixture: Decodable {
        struct Edge: Decodable {
            let stableID: String
            let curve: Curve3D
            let startParameter: Double
            let endParameter: Double
            let startPoint: Point3D
            let endPoint: Point3D
            let surfaceParameterCurve: SurfaceParameterCurve

            var edge: BRepSewingEdge {
                BRepSewingEdge(stableID: stableID, curve: curve,
                    startParameter: startParameter, endParameter: endParameter,
                    startPoint: startPoint, endPoint: endPoint,
                    surfaceParameterCurve: surfaceParameterCurve)
            }
        }
        let surface: Surface3D
        let terminal: Edge
        let boundary: [Edge]
    }

    @Test func terminalIntersectsOriginalFaceBoundary() throws {
        try verifyBoundary(fixtureName: "NativeTerminalTrim")
    }

    @Test(arguments: ["NativeTerminalTrim", "SecondNativeTerminalTrim"])
    func secondOrderTerminalEvaluationMatchesFullDifferential(fixtureName: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureName).json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        guard case .implicit(let implicit) = fixture.terminal.curve else {
            Issue.record("The terminal must be an implicit curve."); return
        }
        let admitted = try ValidatedCurve3D(fixture.terminal.curve, tolerance: tolerance)
        for index in Set([0, implicit.cells.count / 2, implicit.cells.count - 1]).sorted() {
            // Graph cells have independent parameter speeds; differences must
            // stay inside one cell rather than crossing its reparameterization.
            let fraction = (Double(index) + 0.37) / Double(implicit.cells.count)
            let full = try implicit.differential(atNormalizedFraction: fraction, tolerance: tolerance)
            let lower = try admitted.differentialGeometry(at: fraction)
            #expect((lower.position - full.position).length <= tolerance.distance)
            #expect((lower.firstDerivative - full.firstDerivative).length <= tolerance.relative)
            #expect((lower.secondDerivative - full.secondDerivative).length <= tolerance.relative)
            let step = 1e-5 / Double(implicit.cells.count)
            let before = try admitted.differentialGeometry(at: fraction - step).firstDerivative
            let after = try admitted.differentialGeometry(at: fraction + step).firstDerivative
            #expect(((after - before) / (2 * step) - lower.secondDerivative).length < 1e-5)
        }
    }


    @Test func secondTerminalIntersectsOriginalFaceBoundary() throws {
        try verifyBoundary(fixtureName: "SecondNativeTerminalTrim")
    }

    @Test(arguments: ["NativeTerminalTrim", "SecondNativeTerminalTrim"])
    func terminalTrimsBlendPatch(fixtureName: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureName).json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        guard case .implicit(let implicit) = fixture.terminal.curve,
              case .procedural(.rollingBall(let blend)) = implicit.firstSurface else {
            Issue.record("A native terminal must retain its original blend surface."); return
        }
        let edge = BRepSewingEdge(stableID: fixture.terminal.stableID, curve: fixture.terminal.curve,
            startParameter: 0, endParameter: 1, startPoint: fixture.terminal.startPoint,
            endPoint: fixture.terminal.endPoint,
            surfaceParameterCurve: .certifiedImplicit(try .init(intersection: implicit,
                role: .first, tolerance: tolerance)))
        let atStart = fixtureName == "SecondNativeTerminalTrim"
        let rectangular = try RollingBallBlendPatchBuilder().build(blend: blend,
            stableID: "untrimmed-blend", orientation: .forward,
            parentSubshapeIDs: [], tolerance: tolerance)
        #expect(rectangular.loops[0].edges[0].startParameter == 0)
        #expect(rectangular.loops[0].edges[0].endParameter == 1)
        let retainedRange = try ScalarInterval(lower: atStart ? 0 : 0.25, upper: atStart ? 0.75 : 1)
        let patch = try RollingBallBlendPatchBuilder().build(blend: blend,
            stableID: "trimmed-blend", orientation: .reversed, parentSubshapeIDs: [],
            uRange: retainedRange,
            terminal: atStart ? .start(edge) : .end(edge), tolerance: tolerance)
        #expect(patch.surface == implicit.firstSurface)
        let loop = try #require(patch.loops.first)
        #expect(loop.edges.count == 4)
        let shared = try #require(loop.edges.first { $0.stableID == edge.stableID })
        #expect(shared.curve == edge.curve)
        #expect(shared.startPoint == edge.endPoint)
        #expect(shared.endPoint == edge.startPoint)
        #expect(loop.edges.contains { $0.curve == blend.firstContact })
        #expect(loop.edges.contains { $0.curve == blend.secondContact })
        let firstRail = try #require(loop.edges.first { $0.curve == blend.firstContact })
        #expect(atStart ? firstRail.startParameter == retainedRange.upper
            : firstRail.endParameter == retainedRange.lower)
        try patch.validate(tolerance: tolerance)
        let builder = RollingBallBlendPatchBuilder()
        let junction = atStart ? retainedRange.upper : retainedRange.lower
        for candidate in [edge, try BRepSewingPatchOrientationAdapter().reversed(edge, tolerance: tolerance)] {
            let normalized = try builder.build(blend: blend, stableID: "trimmed-blend",
                orientation: .reversed, parentSubshapeIDs: [], retainingJunction: junction,
                terminal: candidate, tolerance: tolerance)
            #expect(normalized.surface == patch.surface)
            #expect(normalized.orientation == patch.orientation)
            #expect(normalized.loops.count == patch.loops.count)
            #expect(normalized.loops[0].edges.count == loop.edges.count)
            for (actual, expected) in zip(normalized.loops[0].edges, loop.edges) {
                #expect(actual.stableID == expected.stableID)
                #expect(actual.curve == expected.curve)
                #expect(actual.startParameter == expected.startParameter)
                #expect(actual.endParameter == expected.endParameter)
                #expect(actual.startPoint == expected.startPoint)
                #expect(actual.endPoint == expected.endPoint)
                #expect(actual.surfaceParameterCurve == expected.surfaceParameterCurve)
                #expect(actual.parentSubshapeIDs == expected.parentSubshapeIDs)
                #expect(actual.startVertexParentSubshapeIDs == expected.startVertexParentSubshapeIDs)
                #expect(actual.endVertexParentSubshapeIDs == expected.endVertexParentSubshapeIDs)
            }
        }
        #expect(throws: KernelError.self) {
            _ = try RollingBallBlendPatchBuilder().build(blend: blend,
                stableID: "invalid-terminal", orientation: .forward, parentSubshapeIDs: [],
                terminal: atStart ? .end(edge) : .start(edge), tolerance: tolerance)
        }
        if atStart {
            // Both endpoints lie below U=0.17, but the interior exceeds it.
            #expect(throws: KernelError.self) {
                _ = try builder.build(blend: blend, stableID: "crossing-junction",
                    orientation: .forward, parentSubshapeIDs: [], retainingJunction: 0.17,
                    terminal: edge, tolerance: tolerance)
            }
            #expect(throws: KernelError.self) {
                _ = try RollingBallBlendPatchBuilder().build(blend: blend,
                    stableID: "crossing-terminal", orientation: .forward, parentSubshapeIDs: [],
                    uRange: ScalarInterval(lower: 0, upper: 0.17), terminal: .start(edge),
                    tolerance: tolerance)
            }
        }
    }

    @Test(.timeLimit(.minutes(2)), arguments: ["NativeTerminalTrim", "SecondNativeTerminalTrim"])
    func nativeTerminalsJoinRetainedNeighbors(fixtureName: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureName).json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        let original = BRepSewingFacePatch(stableID: "neighbor", surface: fixture.surface,
            orientation: .forward, loops: [.init(stableID: "boundary", role: .outer,
                edges: fixture.boundary.map(\.edge))])
        let sewn = try DefaultBRepSewer().sew(.init(featureID: FeatureID(), bodyKind: .sheet,
            shells: [.init(stableID: "neighbor-shell", patches: [original])]), tolerance: tolerance)
        let faceID = try #require(sewn.brep.faces.keys.first)
        let partition = try BooleanOpenFaceArrangementBuilder(sourceContactTolerance: tolerance).build(
            faceID: faceID, boundaries: [.init(reference: .init(
                facePair: .init(targetFaceID: faceID, toolFaceID: faceID), componentID: .init(ordinal: 0)),
                segmentOrdinal: 0, faceID: faceID, edge: fixture.terminal.edge,
                forwardLeftAction: .keep, forwardRightAction: .keep, forcedPartitioning: true)],
            model: sewn.brep, sourceSubshapes: sewn.subshapes, tolerance: tolerance)
        #expect(partition.isPartitioned)
        #expect(partition.patches.count == 2)
        let corner = fixture.boundary[fixtureName == "NativeTerminalTrim" ? 1 : 2].endPoint
        let retained = partition.patches.filter { patch in
            !patch.loops.contains { loop in loop.edges.contains {
                ($0.startPoint - corner).length <= tolerance.distance
                    || ($0.endPoint - corner).length <= tolerance.distance
            } }
        }
        #expect(retained.count == 1)
        for patch in retained {
            #expect(patch.surface == fixture.surface)
            try patch.validate(tolerance: tolerance)
            guard case .implicit(let implicit) = fixture.terminal.curve,
                  case .procedural(.rollingBall(let blend)) = implicit.firstSurface else {
                Issue.record("The terminal boundary must retain its blend support."); return
            }
            let shared = try #require(patch.loops.flatMap(\.edges).first { $0.curve == fixture.terminal.curve })
            let terminal = BRepSewingEdge(stableID: "blend-terminal", curve: fixture.terminal.curve,
                startParameter: 0, endParameter: 1, startPoint: fixture.terminal.startPoint,
                endPoint: fixture.terminal.endPoint, surfaceParameterCurve: .certifiedImplicit(
                    try .init(intersection: implicit, role: .first, tolerance: tolerance)))
            let atStart = fixtureName == "SecondNativeTerminalTrim"
            let blendPatch = try RollingBallBlendPatchBuilder().build(blend: blend,
                stableID: "terminal-blend", orientation: shared.startParameter < shared.endParameter ? .reversed : .forward,
                parentSubshapeIDs: [], uRange: ScalarInterval(lower: atStart ? 0 : 0.5,
                    upper: atStart ? 0.5 : 1), terminal: atStart ? .start(terminal) : .end(terminal),
                tolerance: tolerance)
            let joined = try DefaultBRepSewer().sew(.init(featureID: FeatureID(), bodyKind: .sheet,
                shells: [.init(stableID: "native-terminal-and-retained-neighbor", patches: [patch, blendPatch])]),
                tolerance: tolerance)
            #expect(joined.validatedBRep.validationLevel == .exact)
            #expect(joined.brep.faces.count == 2)
            let neighborEdge = try #require(joined.stableReferences[.edge(shared.stableID)])
            #expect(neighborEdge == joined.stableReferences[.edge(terminal.stableID)])
            let uses = Dictionary(grouping: joined.brep.loops.values.flatMap(\.edges), by: \.edgeID)
            #expect(uses.values.filter { $0.count == 2 }.count == 1)
        }
    }

    private func verifyBoundary(fixtureName: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixtureName).json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        var contacts: [Point3D] = []
        for (index, source) in fixture.boundary.enumerated() {
            print("Native terminal boundary edge \(index): \(source.stableID)")
            let result = try ExactTrimEdgeIntersector().intersections(
                source.edge, fixture.terminal.edge,
                sharedSurface: fixture.surface, tolerance: tolerance)
            guard case .subdivisionPoints(let points) = result else {
                Issue.record("A terminal crossing must not coincide with a source boundary.")
                continue
            }
            contacts.append(contentsOf: points)
        }
        #expect(contacts.count == 2)
        for endpoint in [fixture.terminal.startPoint, fixture.terminal.endPoint] {
            #expect(contacts.contains { ($0 - endpoint).length <= tolerance.distance })
        }
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: fixture.terminal.curve, surface: fixture.surface,
                options: .init(maximumSubdivisionCells: 1), tolerance: tolerance)
            Issue.record("A graph-cell budget smaller than the native atlas must fail.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }
}
