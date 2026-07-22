import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Coincident cylindrical face arrangement")
struct CoincidentCylindricalFaceArrangementTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func partiallyOverlappingCylinderTrimsProduceExactIntersectionPatch() throws {
        let target = try cylindricalSheet(
            lowerU: 0.2,
            upperU: 2.2,
            lowerV: -1.0,
            upperV: 1.0,
            stablePrefix: "cylinder-target"
        )
        let tool = try cylindricalSheet(
            lowerU: 1.2,
            upperU: 3.2,
            lowerV: -0.5,
            upperV: 0.5,
            stablePrefix: "cylinder-tool"
        )
        let model = try BRepModelCombiner().combined([target.brep, tool.brep])
        let targetFaceID = try faceID(in: target.brep)
        let toolFaceID = try faceID(in: tool.brep)
        let split = BooleanFaceSplit(
            facePair: BooleanFacePairCandidate(
                targetFaceID: targetFaceID,
                toolFaceID: toolFaceID
            ),
            components: [BooleanFaceSplitComponent(
                id: BooleanFaceSplitComponentID(ordinal: 0),
                geometry: .coincident
            )]
        )
        let resolution = try CoincidentBooleanFaceOwnershipResolver().resolve(
            operation: .intersect,
            uvSplitGraph: BooleanUVSplitGraph(splits: [split]),
            model: model,
            tolerance: tolerance
        )
        #expect(resolution.forcedActions.isEmpty)
        #expect(resolution.partiallyCoincidentPairs.count == 1)
        let sourceSubshapes = target.subshapes.entries.merging(
            tool.subshapes.entries
        ) { current, _ in current }
        let arrangement = try CoincidentBooleanFaceArrangementBoundaryBuilder().build(
            operation: .intersect,
            pairs: resolution.partiallyCoincidentPairs,
            model: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        )
        #expect(arrangement.constantActions[toolFaceID] == .discard)
        let targetBoundaries = arrangement.boundaries.filter {
            $0.faceID == targetFaceID
        }
        #expect(targetBoundaries.count == 4)

        let result = try BooleanOpenFaceArrangementBuilder().build(
            faceID: targetFaceID,
            boundaries: targetBoundaries,
            model: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        )

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        #expect(patch.loops.count == 1)
        #expect(patch.loops[0].edges.count == 4)
        let areaBounds = try patch.loops[0].edges.reduce(
            into: (lower: 0.0, upper: 0.0)
        ) { result, edge in
            let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
                for: edge.surfaceParameterCurve,
                uShift: 0.0,
                requestedWidth: tolerance.distance * tolerance.distance,
                tolerance: tolerance
            )
            result.lower += bounds.lower
            result.upper += bounds.upper
        }
        #expect(areaBounds.lower > 0.999)
        #expect(areaBounds.upper < 1.001)
    }

    private func cylindricalSheet(
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double,
        stablePrefix: String
    ) throws -> PlanarSheetTestFixture {
        let surface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let bottomStart = try surface.point(
            u: lowerU,
            v: lowerV,
            tolerance: tolerance
        )
        let bottomEnd = try surface.point(
            u: upperU,
            v: lowerV,
            tolerance: tolerance
        )
        let topStart = try surface.point(
            u: upperU,
            v: upperV,
            tolerance: tolerance
        )
        let topEnd = try surface.point(
            u: lowerU,
            v: upperV,
            tolerance: tolerance
        )
        let height = upperV - lowerV
        let edges = [
            BRepSewingEdge(
                stableID: "\(stablePrefix):bottom",
                curve: .circle(Circle3D(
                    center: Point3D(x: 0.0, y: 0.0, z: lowerV),
                    normal: .unitZ,
                    radius: 1.0
                )),
                startParameter: lowerU,
                endParameter: upperU,
                startPoint: bottomStart,
                endPoint: bottomEnd,
                surfaceParameterCurve: .constantV(
                    v: lowerV,
                    uStart: lowerU,
                    uEnd: upperU
                )
            ),
            BRepSewingEdge(
                stableID: "\(stablePrefix):right",
                curve: .line(Line3D(origin: bottomEnd, direction: .unitZ)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: bottomEnd,
                endPoint: topStart,
                surfaceParameterCurve: .constantU(
                    u: upperU,
                    vStart: lowerV,
                    vEnd: upperV
                )
            ),
            BRepSewingEdge(
                stableID: "\(stablePrefix):top",
                curve: .circle(Circle3D(
                    center: Point3D(x: 0.0, y: 0.0, z: upperV),
                    normal: .unitZ,
                    radius: 1.0
                )),
                startParameter: upperU,
                endParameter: lowerU,
                startPoint: topStart,
                endPoint: topEnd,
                surfaceParameterCurve: .constantV(
                    v: upperV,
                    uStart: upperU,
                    uEnd: lowerU
                )
            ),
            BRepSewingEdge(
                stableID: "\(stablePrefix):left",
                curve: .line(Line3D(origin: topEnd, direction: .unitZ * -1.0)),
                startParameter: 0.0,
                endParameter: height,
                startPoint: topEnd,
                endPoint: bottomStart,
                surfaceParameterCurve: .constantU(
                    u: lowerU,
                    vStart: upperV,
                    vEnd: lowerV
                )
            ),
        ]
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

    private func faceID(in model: BRepModel) throws -> FaceID {
        let body = try #require(model.bodies.values.first)
        let shell = try #require(model.shells[body.shellIDs[0]])
        return try #require(shell.faceIDs.first)
    }
}
