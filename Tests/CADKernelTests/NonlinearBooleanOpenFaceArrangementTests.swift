import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Nonlinear Boolean open-face arrangement")
struct NonlinearBooleanOpenFaceArrangementTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func exactSurfaceLiftPcurvesIntersectWithoutRationalModelCurveFallback() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let horizontal = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: -0.020, y: 0.0),
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.020, y: 0.0),
            ],
            weights: [1.0, 1.2, 1.0]
        )
        let vertical = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: -0.020),
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.0, y: 0.020),
            ],
            weights: [1.0, 0.8, 1.0]
        )
        let first = try surfaceLiftEdge(
            stableID: "surface-lift-crossing:horizontal",
            surface: surface,
            parameterCurve: horizontal
        )
        let second = try surfaceLiftEdge(
            stableID: "surface-lift-crossing:vertical",
            surface: surface,
            parameterCurve: vertical
        )

        let result = try ExactTrimEdgeIntersector().intersections(
            first,
            second,
            tolerance: tolerance
        )
        guard case let .subdivisionPoints(points) = result else {
            Issue.record("Transverse surface-lift pcurves must not be classified as coincident.")
            return
        }
        let expected = try surface.point(u: 0.0, v: 0.0, tolerance: tolerance)
        #expect(points.count == 1)
        #expect(points[0].isApproximatelyEqual(to: expected, tolerance: tolerance.distance))
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalQuadraticBoundaryUsesExactNonlinearCrossingSubdivision() throws {
        let fixture = try makeFixture()
        let boundary = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-arrangement:quadratic",
            startParameter: 0.0,
            endParameter: 1.0,
            segmentOrdinal: 0
        )

        let result = try build(fixture: fixture, boundaries: [boundary])

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        #expect(patch.loops.count == 1)
        #expect(patch.loops[0].edges.contains { edge in
            if case .bSpline = edge.curve { return true }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func partiallyOverlappingRationalBoundariesMergeExactSharedSpan() throws {
        let fixture = try makeFixture()
        let first = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-overlap:first",
            startParameter: 0.0,
            endParameter: 0.75,
            segmentOrdinal: 0
        )
        let second = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-overlap:second",
            startParameter: 0.25,
            endParameter: 1.0,
            segmentOrdinal: 1
        )

        let result = try build(fixture: fixture, boundaries: [first, second])

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        let splineEdges = patch.loops.flatMap(\.edges).filter { edge in
            if case .bSpline = edge.curve { return true }
            return false
        }
        #expect(splineEdges.count == 3)
        #expect(splineEdges.contains { edge in
            abs(edge.startParameter - 0.25) <= tolerance.relative
                && abs(edge.endParameter - 0.75) <= tolerance.relative
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func quadraticBoundaryTangentToSourceEdgeBuildsValidatedRegion() throws {
        let fixture = try makeFixture(controlY: 0.020)
        let boundary = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-tangent:quadratic",
            startParameter: 0.0,
            endParameter: 1.0,
            segmentOrdinal: 0,
            forwardLeftAction: .discard,
            forwardRightAction: .keep
        )

        let result = try build(fixture: fixture, boundaries: [boundary])

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        let splineEdges = patch.loops.flatMap(\.edges).filter { edge in
            if case .bSpline = edge.curve { return true }
            return false
        }
        #expect(splineEdges.count == 2)
        let tangentPoint = try fixture.curve.point(
            at: 0.5,
            tolerance: tolerance
        )
        #expect(splineEdges.contains { edge in
            edge.startPoint.isApproximatelyEqual(
                to: tangentPoint,
                tolerance: tolerance.distance
            ) || edge.endPoint.isApproximatelyEqual(
                to: tangentPoint,
                tolerance: tolerance.distance
            )
        })
    }

    private func build(
        fixture: Fixture,
        boundaries: [BooleanFaceArrangementBoundary]
    ) throws -> BooleanOpenFaceArrangementBuilder.Result {
        try BooleanOpenFaceArrangementBuilder().build(
            faceID: fixture.face.id,
            boundaries: boundaries,
            model: fixture.source.brep,
            sourceSubshapes: fixture.source.subshapes.entries,
            tolerance: tolerance
        )
    }

    private func makeFixture(controlY: Double = 0.006) throws -> Fixture {
        let source = try PlanarSheetTestFixture.make(
            featureID: FeatureID(),
            tolerance: tolerance
        )
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let controlPoints = [
            Point3D(x: -0.020, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: controlY, z: 0.0),
            Point3D(x: 0.020, y: 0.0, z: 0.0),
        ]
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: controlPoints,
            weights: [1.0, 1.0, 1.0]
        )
        try curve.validate(tolerance: tolerance)
        let projectedControls = try controlPoints.map { point in
            let parameter = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            return Point2D(x: parameter.u, y: parameter.v)
        }
        let pcurve = BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: projectedControls,
            weights: curve.weights
        )
        try pcurve.validate(tolerance: tolerance)
        return Fixture(
            source: source,
            face: face,
            curve: curve,
            pcurve: pcurve
        )
    }

    private func makeBoundary(
        fixture: Fixture,
        stableID: String,
        startParameter: Double,
        endParameter: Double,
        segmentOrdinal: Int,
        forwardLeftAction: BooleanRegionSelectionAction = .keep,
        forwardRightAction: BooleanRegionSelectionAction = .discard
    ) throws -> BooleanFaceArrangementBoundary {
        let pair = BooleanFacePairCandidate(
            targetFaceID: fixture.face.id,
            toolFaceID: FaceID()
        )
        let startPoint = try fixture.curve.point(
            at: startParameter,
            tolerance: tolerance
        )
        let endPoint = try fixture.curve.point(
            at: endParameter,
            tolerance: tolerance
        )
        let pcurve = try fixture.pcurve.trimmed(
            from: startParameter,
            to: endParameter,
            tolerance: tolerance
        )
        return BooleanFaceArrangementBoundary(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: BooleanFaceSplitComponentID(ordinal: segmentOrdinal)
            ),
            segmentOrdinal: segmentOrdinal,
            faceID: fixture.face.id,
            edge: BRepSewingEdge(
                stableID: stableID,
                curve: .bSpline(fixture.curve),
                startParameter: startParameter,
                endParameter: endParameter,
                startPoint: startPoint,
                endPoint: endPoint,
                surfaceParameterCurve: .bSpline(pcurve)
            ),
            forwardLeftAction: forwardLeftAction,
            forwardRightAction: forwardRightAction
        )
    }

    private func surfaceLiftEdge(
        stableID: String,
        surface: Surface3D,
        parameterCurve: BSplineCurve2D
    ) throws -> BRepSewingEdge {
        let pcurve = SurfaceParameterCurve.bSpline(parameterCurve)
        let lift = SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve)
        try lift.validate(tolerance: tolerance)
        let curve = Curve3D.surfaceLift(lift)
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try curve.point(at: 0.0, tolerance: tolerance),
            endPoint: try curve.point(at: 1.0, tolerance: tolerance),
            surfaceParameterCurve: pcurve
        )
    }

    private struct Fixture {
        let source: PlanarSheetTestFixture
        let face: Face
        let curve: BSplineCurve3D
        let pcurve: BSplineCurve2D
    }
}
