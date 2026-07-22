import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel
import Foundation
import Testing

@Suite("Exact analytic face pcurve construction")
struct ExactFacePcurveBuilderTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func constructsConeCoordinateCirclePcurve() throws {
        let surface = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 4.0
        ))
        let curve = Curve3D.circle(Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: 1.0),
            normal: .unitZ,
            radius: 1.0
        ))

        let pcurve = try reconstructedPcurve(surface: surface, curve: curve)
        guard case let .constantV(v, _, _) = pcurve else {
            Issue.record("A cone coordinate circle must produce an exact constant-V pcurve.")
            return
        }
        #expect(abs(v - sqrt(2.0)) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func constructsTorusCoordinateCirclePcurve() throws {
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let curve = Curve3D.circle(Circle3D(
            center: Point3D(x: 0.0, y: 0.0, z: 1.0),
            normal: .unitZ,
            radius: 3.0
        ))

        let pcurve = try reconstructedPcurve(surface: surface, curve: curve)
        guard case let .constantV(v, _, _) = pcurve else {
            Issue.record("A torus coordinate circle must produce an exact constant-V pcurve.")
            return
        }
        #expect(abs(v - Double.pi / 2.0) <= tolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func constructsArbitrarySphericalGreatCirclePcurve() throws {
        let normal = try Vector3D(x: 1.0, y: 2.0, z: 3.0).normalized(
            tolerance: tolerance.distance
        )
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: normal,
            radius: 2.0
        ))

        let pcurve = try reconstructedPcurve(surface: surface, curve: curve)
        guard case .sphericalGreatCircle = pcurve else {
            Issue.record("An arbitrary sphere great circle must retain an exact spherical pcurve.")
            return
        }
        try pcurve.validate(on: surface, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsNonCoordinateSmallCircleWithoutApproximation() throws {
        let normal = try Vector3D(x: 1.0, y: 1.0, z: 0.0).normalized(
            tolerance: tolerance.distance
        )
        let center = Point3D(x: normal.x, y: normal.y, z: normal.z)
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let curve = Curve3D.circle(Circle3D(
            center: center,
            normal: normal,
            radius: sqrt(3.0)
        ))

        do {
            _ = try reconstructedPcurve(surface: surface, curve: curve)
            Issue.record("A non-coordinate small circle must not receive an approximate pcurve.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func reusesExactSurfaceLiftPcurveForTrimmedEdge() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let source = SurfaceParameterCurve.affine(
            origin: Point2D(x: 1.0, y: -2.0),
            direction: Point2D(x: 3.0, y: 4.0),
            startParameter: 2.0,
            endParameter: 5.0
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: source
        ))

        let pcurve = try reconstructedPcurve(
            surface: surface,
            curve: curve,
            startParameter: 0.2,
            endParameter: 0.75
        )
        let expected = try source.subcurve(
            fromNormalizedFraction: 0.2,
            toNormalizedFraction: 0.75,
            tolerance: tolerance
        )
        #expect(pcurve == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func reversesExactSurfaceLiftPcurveForReversedCoedge() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let source = SurfaceParameterCurve.harmonic(
            center: Point2D(x: 2.0, y: 3.0),
            cosine: Point2D(x: 1.0, y: 0.0),
            sine: Point2D(x: 0.0, y: 2.0),
            startParameter: 0.0,
            endParameter: Double.pi
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: source
        ))

        let pcurve = try reconstructedPcurve(
            surface: surface,
            curve: curve,
            startParameter: 0.125,
            endParameter: 0.625,
            orientation: .reversed
        )
        let expected = try source.subcurve(
            fromNormalizedFraction: 0.125,
            toNormalizedFraction: 0.625,
            tolerance: tolerance
        ).reversed(tolerance: tolerance)
        #expect(pcurve == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func constructsProjectedHyperbolaPcurveOnPlaneAndPreservesDirection() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let curve = Curve3D.analytic(.hyperbola(Hyperbola3D(
            center: .origin,
            normal: .unitZ,
            transverseAxis: .unitX,
            transverseRadius: 2.0,
            conjugateRadius: 1.0
        )))

        let pcurve = try reconstructedPcurve(
            surface: surface,
            curve: curve,
            startParameter: -0.75,
            endParameter: 0.5,
            orientation: .reversed
        )
        guard case let .projectedAnalytic(projected) = pcurve else {
            Issue.record("A planar hyperbola must produce an exact projected analytic pcurve.")
            return
        }
        #expect(projected.startParameter == 0.5)
        #expect(projected.endParameter == -0.75)
        try pcurve.validate(on: surface, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func constructsProjectedHyperbolaPcurveOnCone() throws {
        let surface = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 4.0
        ))
        let curve = Curve3D.analytic(.hyperbola(Hyperbola3D(
            center: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            transverseAxis: .unitZ,
            transverseRadius: 1.0,
            conjugateRadius: 1.0
        )))

        let pcurve = try reconstructedPcurve(
            surface: surface,
            curve: curve,
            startParameter: -0.5,
            endParameter: 0.5
        )
        guard case .projectedAnalytic = pcurve else {
            Issue.record("A cone-supported hyperbola must produce an exact projected analytic pcurve.")
            return
        }
        try pcurve.validate(on: surface, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func constructsTrimmedReversedRationalBSplinePcurveOnPlane() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -2.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 3.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.5, 1.0]
        ))

        let pcurve = try reconstructedPcurve(
            surface: surface,
            curve: curve,
            startParameter: 0.15,
            endParameter: 0.85,
            orientation: .reversed
        )
        guard case let .bSpline(projected) = pcurve else {
            Issue.record("A planar rational B-spline must retain an exact rational pcurve.")
            return
        }
        #expect(projected.degree == 2)
        #expect(projected.isRational)
        let pcurveStart = try pcurve.startParameter(tolerance: tolerance)
        let expectedStart = try surface.parameterProjection(
            of: curve.point(at: 0.85, tolerance: tolerance),
            tolerance: tolerance
        )
        #expect(abs(pcurveStart.u - expectedStart.u) <= tolerance.distance)
        #expect(abs(pcurveStart.v - expectedStart.v) <= tolerance.distance)
        try pcurve.validate(on: surface, tolerance: tolerance)
    }

    private func reconstructedPcurve(
        surface: Surface3D,
        curve: Curve3D,
        startParameter: Double = 0.0,
        endParameter: Double = Double.pi / 2.0,
        orientation: Orientation = .forward
    ) throws -> SurfaceParameterCurve {
        let surfaceID = SurfaceID()
        let curveID = CurveID()
        let edgeID = EdgeID()
        let loopID = LoopID()
        let faceID = FaceID()
        let startVertexID = VertexID()
        let endVertexID = VertexID()
        var model = BRepModel()
        model.geometry.surfaces[surfaceID] = surface
        model.geometry.curves[curveID] = curve
        model.vertices[startVertexID] = Vertex(
            id: startVertexID,
            point: try curve.point(at: startParameter, tolerance: tolerance)
        )
        model.vertices[endVertexID] = Vertex(
            id: endVertexID,
            point: try curve.point(at: endParameter, tolerance: tolerance)
        )
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(startParameter: startParameter, endParameter: endParameter)
        )
        model.loops[loopID] = Loop(
            id: loopID,
            role: .outer,
            coedges: [Coedge(edgeID: edgeID, orientation: orientation)]
        )
        model.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: [loopID],
            orientation: .forward
        )

        try ExactFacePcurveBuilder().populateMissingPcurves(
            in: &model,
            tolerance: tolerance
        )
        guard let pcurve = model.loops[loopID]?.coedges.first?.surfaceParameterCurve else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Exact pcurve reconstruction did not publish a result."
            )
        }
        return pcurve
    }
}
