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

    private func reconstructedPcurve(
        surface: Surface3D,
        curve: Curve3D
    ) throws -> SurfaceParameterCurve {
        let surfaceID = SurfaceID()
        let curveID = CurveID()
        let edgeID = EdgeID()
        let loopID = LoopID()
        let faceID = FaceID()
        let startVertexID = VertexID()
        let endVertexID = VertexID()
        let startParameter = 0.0
        let endParameter = Double.pi / 2.0
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
            coedges: [Coedge(edgeID: edgeID, orientation: .forward)]
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
