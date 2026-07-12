import CADCore
import CADGeometry
import Testing

struct GeometryKernelTests {
    @Test
    func boundingBoxContainsAndUnions() throws {
        let first = try BoundingBox3D(
            minimum: Point3D(x: 0.0, y: 0.0, z: 0.0),
            maximum: Point3D(x: 1.0, y: 1.0, z: 1.0)
        )
        let second = try BoundingBox3D(
            minimum: Point3D(x: 1.0, y: -1.0, z: 0.5),
            maximum: Point3D(x: 2.0, y: 0.0, z: 1.5)
        )
        let union = try first.union(second)
        #expect(first.contains(Point3D(x: 0.5, y: 0.5, z: 0.5)))
        #expect(first.intersects(second))
        #expect(union.minimum == Point3D(x: 0.0, y: -1.0, z: 0.0))
        #expect(union.maximum == Point3D(x: 2.0, y: 1.0, z: 1.5))
    }

    @Test
    func uncertainOrientationFailsClosed() throws {
        let a = Point3D(x: 0.0, y: 0.0, z: 0.0)
        let b = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let c = Point3D(x: 0.0, y: 1.0, z: 0.0)
        let d = Point3D(x: 0.0, y: 0.0, z: 1.0)
        let sign = try RobustPredicates.orientation3D(
            a,
            b,
            c,
            relativeTo: d,
            determinantTolerance: 1.0e-12
        )
        #expect(sign == .negative)
    }

    @Test
    func sphereDifferentialGeometryIsOrthonormal() throws {
        let sphere = AnalyticSurface3D.sphere(
            center: .origin,
            radius: 2.0
        )
        let differential = try sphere.differentialGeometry(u: 0.4, v: 0.3)
        #expect(abs(differential.normal.length - 1.0) < 1.0e-12)
        #expect(abs((differential.position - Point3D.origin).length - 2.0) < 1.0e-12)
        let frame = try sphere.uvnFrame(u: 0.4, v: 0.3)
        #expect(abs(frame.u.dot(frame.v)) < 1.0e-12)
        #expect(abs(frame.u.cross(frame.v).dot(frame.normal) - 1.0) < 1.0e-12)
        #expect(abs(differential.meanCurvature + 0.5) < 1.0e-12)
    }

    @Test
    func ellipseHasExactEndpointAndCurvature() throws {
        let ellipse = AnalyticCurve3D.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 4.0,
            minorRadius: 2.0
        )
        let differential = try ellipse.differentialGeometry(at: 0.0)
        #expect(differential.position == Point3D(x: 4.0, y: 0.0, z: 0.0))
        #expect(differential.curvature.isFinite)
    }

    @Test
    func rationalBezierCurveEvaluatesHomogeneousDerivatives() throws {
        let curve = RationalBSplineCurve3D(
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
            ],
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            degree: 2
        )
        let differential = try curve.differentialGeometry(at: 0.5)
        #expect(abs(differential.position.x - 1.0) < 1.0e-12)
        #expect(abs(differential.position.y - 0.5) < 1.0e-12)
        #expect(differential.firstDerivative.length > 0.0)
    }

    @Test
    func rationalSurfaceEvaluatesPositionAndNormal() throws {
        let surface = RationalBSplineSurface3D(
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 0.0, y: 1.0, z: 0.0)],
                [Point3D(x: 1.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ],
            knotsU: [0.0, 0.0, 1.0, 1.0],
            knotsV: [0.0, 0.0, 1.0, 1.0],
            degreeU: 1,
            degreeV: 1
        )
        let differential = try surface.differentialGeometry(u: 0.25, v: 0.75)
        #expect(abs(differential.position.x - 0.25) < 1.0e-12)
        #expect(abs(differential.position.y - 0.75) < 1.0e-12)
        #expect(differential.normal == .unitZ)
    }
}
