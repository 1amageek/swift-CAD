import CADCore
import CADGeometry
@testable import CADTopology
import Testing

@Suite("Certified B-rep edge length")
struct DefaultBRepEdgeLengthEvaluatorTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func unboundedLineUsesTopologicalEndpoints() throws {
        let curveID = CurveID()
        let start = Vertex(point: .origin)
        let end = Vertex(point: Point3D(x: 3.0, y: 0.0, z: 0.0))
        let edge = Edge(
            curveID: curveID,
            startVertexID: start.id,
            endVertexID: end.id
        )
        let model = BRepModel(
            geometry: GeometryStore(curves: [
                curveID: .line(Line3D(origin: .origin, direction: .unitX)),
            ]),
            edges: [edge.id: edge],
            vertices: [start.id: start, end.id: end]
        )

        let length = try DefaultBRepEdgeLengthEvaluator().lengthEnclosure(
            of: edge,
            in: model,
            tolerance: tolerance
        )

        #expect(length.lowerBound <= 3.0)
        #expect(length.upperBound >= 3.0)
        #expect(abs(length.midpoint - 3.0) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rigidImageUsesCanonicalCurveArcLength() throws {
        let source = Curve3D.bSpline(BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.0, y: 4.0, z: 0.0),
                Point3D(x: 2.0, y: 6.0, z: 0.0),
                Point3D(x: 8.0, y: 6.0, z: 0.0),
            ]
        ))
        let transform = try RigidTransform3D.rotated(
            around: .origin,
            direction: .unitZ,
            angle: Double.pi * 0.5,
            tolerance: tolerance
        )
        let curve = Curve3D.rigidImage(try RigidImageCurve3D(
            source: source,
            transform: transform,
            tolerance: tolerance
        ))
        let curveID = CurveID()
        let start = Vertex(point: try curve.point(at: 0.0, tolerance: tolerance))
        let end = Vertex(point: try curve.point(at: 1.0, tolerance: tolerance))
        let edge = Edge(
            curveID: curveID,
            startVertexID: start.id,
            endVertexID: end.id,
            trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
        )
        let model = BRepModel(
            geometry: GeometryStore(curves: [curveID: curve]),
            edges: [edge.id: edge],
            vertices: [start.id: start, end.id: end]
        )

        let actual = try DefaultBRepEdgeLengthEvaluator().lengthEnclosure(
            of: edge,
            in: model,
            tolerance: tolerance
        )
        let expected = try DefaultCurveArcLengthResolver().enclosure(
            of: curve,
            over: ScalarInterval(lower: 0.0, upper: 1.0),
            tolerance: tolerance
        )

        #expect(actual.lowerBound == expected.lowerBound)
        #expect(actual.upperBound == expected.upperBound)
    }
}
