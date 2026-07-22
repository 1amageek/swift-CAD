import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Coincident Boolean face arrangement boundaries")
struct CoincidentBooleanFaceArrangementBoundaryBuilderTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func nestedCoincidentTrimProducesExactIntersectionPatch() throws {
        let fixture = try fixture(
            targetPoints: rectangle(
                minimumX: -0.020,
                maximumX: 0.020,
                minimumY: -0.010,
                maximumY: 0.010
            ),
            toolPoints: rectangle(
                minimumX: -0.005,
                maximumX: 0.005,
                minimumY: -0.003,
                maximumY: 0.003
            )
        )
        let resolution = try resolve(.intersect, fixture: fixture)
        #expect(resolution.partiallyCoincidentPairs.count == 1)
        #expect(resolution.forcedActions.isEmpty)

        let arrangement = try CoincidentBooleanFaceArrangementBoundaryBuilder().build(
            operation: .intersect,
            pairs: resolution.partiallyCoincidentPairs,
            model: fixture.model,
            sourceSubshapes: fixture.sourceSubshapes,
            tolerance: tolerance
        )
        #expect(arrangement.constantActions[fixture.toolFaceID] == .discard)
        let targetBoundaries = arrangement.boundaries.filter {
            $0.faceID == fixture.targetFaceID
        }
        #expect(targetBoundaries.count == 4)
        #expect(targetBoundaries.allSatisfy { $0.isPartitioning })

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: fixture.targetFaceID,
            boundaries: targetBoundaries,
            model: fixture.model,
            sourceSubshapes: fixture.sourceSubshapes,
            tolerance: tolerance
        )
        #expect(result.isPartitioned)
        let patch = try #require(result.patches.first)
        #expect(result.patches.count == 1)
        try patch.validate(tolerance: tolerance)
        #expect(abs(try signedArea(patch.loops[0])) > 0.000_059)
        #expect(abs(try signedArea(patch.loops[0])) < 0.000_061)
    }

    @Test(.timeLimit(.minutes(1)))
    func crossingCoincidentLinearTrimsAreSubdividedIntoExactOverlap() throws {
        let fixture = try fixture(
            targetPoints: rectangle(
                minimumX: -0.020,
                maximumX: 0.020,
                minimumY: -0.010,
                maximumY: 0.010
            ),
            toolPoints: rectangle(
                minimumX: 0.0,
                maximumX: 0.030,
                minimumY: -0.005,
                maximumY: 0.005
            )
        )
        let resolution = try resolve(.intersect, fixture: fixture)
        let arrangement = try CoincidentBooleanFaceArrangementBoundaryBuilder().build(
            operation: .intersect,
            pairs: resolution.partiallyCoincidentPairs,
            model: fixture.model,
            sourceSubshapes: fixture.sourceSubshapes,
            tolerance: tolerance
        )
        let targetBoundaries = arrangement.boundaries.filter {
            $0.faceID == fixture.targetFaceID
        }
        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: fixture.targetFaceID,
            boundaries: targetBoundaries,
            model: fixture.model,
            sourceSubshapes: fixture.sourceSubshapes,
            tolerance: tolerance
        )

        #expect(result.isPartitioned)
        let patch = try #require(result.patches.first)
        #expect(result.patches.count == 1)
        try patch.validate(tolerance: tolerance)
        #expect(abs(try signedArea(patch.loops[0])) > 0.000_199)
        #expect(abs(try signedArea(patch.loops[0])) < 0.000_201)
        #expect(patch.loops[0].edges.count == 4)
    }

    private func resolve(
        _ operation: BooleanOperation,
        fixture: Fixture
    ) throws -> CoincidentBooleanFaceOwnershipResolver.Resolution {
        try CoincidentBooleanFaceOwnershipResolver().resolve(
            operation: operation,
            uvSplitGraph: BooleanUVSplitGraph(splits: [BooleanFaceSplit(
                facePair: BooleanFacePairCandidate(
                    targetFaceID: fixture.targetFaceID,
                    toolFaceID: fixture.toolFaceID
                ),
                components: [BooleanFaceSplitComponent(
                    id: BooleanFaceSplitComponentID(ordinal: 0),
                    geometry: .coincident
                )]
            )]),
            model: fixture.model,
            tolerance: tolerance
        )
    }

    private func fixture(
        targetPoints: [Point3D],
        toolPoints: [Point3D]
    ) throws -> Fixture {
        let target = try sheet(points: targetPoints, stablePrefix: "target")
        let tool = try sheet(points: toolPoints, stablePrefix: "tool")
        let targetBodyID = try #require(target.brep.bodies.keys.first)
        let toolBodyID = try #require(tool.brep.bodies.keys.first)
        let targetFaceID = try faceID(bodyID: targetBodyID, model: target.brep)
        let toolFaceID = try faceID(bodyID: toolBodyID, model: tool.brep)
        return Fixture(
            model: try BRepModelCombiner().combined([target.brep, tool.brep]),
            targetFaceID: targetFaceID,
            toolFaceID: toolFaceID,
            sourceSubshapes: target.subshapes.entries.merging(tool.subshapes.entries) {
                current, _ in current
            }
        )
    }

    private func sheet(
        points: [Point3D],
        stablePrefix: String
    ) throws -> PlanarSheetTestFixture {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let edges = try points.indices.map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = end - start
            let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
            let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
            return BRepSewingEdge(
                stableID: "\(stablePrefix):edge:\(index)",
                curve: .line(Line3D(
                    origin: start,
                    direction: try delta.normalized(tolerance: tolerance.distance)
                )),
                startParameter: 0.0,
                endParameter: delta.length,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ])
            )
        }
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "\(stablePrefix):shell",
                patches: [BRepSewingFacePatch(
                    stableID: "\(stablePrefix):face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "\(stablePrefix):outer",
                        role: .outer,
                        edges: edges
                    )]
                )]
            )]
        ), tolerance: tolerance)
        return PlanarSheetTestFixture(
            brep: sewn.brep,
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage
        )
    }

    private func faceID(
        bodyID: BodyID,
        model: BRepModel
    ) throws -> FaceID {
        let body = try #require(model.bodies[bodyID])
        let shellID = try #require(body.shellIDs.first)
        let shell = try #require(model.shells[shellID])
        return try #require(shell.faceIDs.first)
    }

    private func rectangle(
        minimumX: Double,
        maximumX: Double,
        minimumY: Double,
        maximumY: Double
    ) -> [Point3D] {
        [
            Point3D(x: minimumX, y: minimumY, z: 0.0),
            Point3D(x: maximumX, y: minimumY, z: 0.0),
            Point3D(x: maximumX, y: maximumY, z: 0.0),
            Point3D(x: minimumX, y: maximumY, z: 0.0),
        ]
    }

    private func signedArea(_ loop: BRepSewingLoop) throws -> Double {
        let points = try loop.edges.map {
            try $0.surfaceParameterCurve.startParameter(tolerance: tolerance)
        }
        return points.indices.reduce(0.0) { result, index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            return result + start.u * end.v - end.u * start.v
        } * 0.5
    }

    private struct Fixture {
        let model: BRepModel
        let targetFaceID: FaceID
        let toolFaceID: FaceID
        let sourceSubshapes: [SubshapeID: TopologyReference]
    }
}
