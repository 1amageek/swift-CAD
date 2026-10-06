import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Original curved draft authority")
struct CurvedHingeDraftAuthorityTests {
    @Test(.timeLimit(.minutes(1)), arguments: [1.0, -1.0])
    func originalCoaxialCylinderHasOneApexForEveryRuling(sign: Double) throws {
        let center = Point3D(x: 0, y: 0, z: 3)
        let circle = Circle3D(center: center, normal: .unitZ, radius: 2)
        let angle = Double.pi / 6
        let result = try CurvedHingeDraftSurfaceBuilder(tolerance: .standard).surface(
            hinge: .circle(circle), start: 0.2, end: 2.7,
            reference: .analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 2)),
            referenceSign: sign, outward: .unitZ, angle: angle, reach: 4)
        guard case let .analytic(.cone(apex, axis, halfAngle)) = result else {
            Issue.record("The original coaxial cylinder must produce its exact cone.")
            return
        }
        let expected = center + Vector3D.unitZ * (sign * 2 * tan(angle))
        #expect((apex - expected).length <= 1e-12)
        #expect(abs(halfAngle - Double.pi / 3) <= 1e-12)
        #expect(axis == Vector3D.unitZ * -sign)
        // Independent non-admission stations check the original ruling, not sampled apex fitting.
        for t in [0.37, 0.91, 1.53, 2.41] {
            let radial = Vector3D(x: cos(t), y: sin(t), z: 0)
            let hingePoint = center + radial * 2
            let ruling = radial * -sign + Vector3D.unitZ * tan(angle)
            #expect((hingePoint + ruling * (sign * 2) - apex).length <= 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func shiftedCylinderCannotBorrowThreeRadialNormals() throws {
        let circle = Circle3D(center: .origin, normal: .unitZ, radius: 1)
        // At 0, pi and 2pi the shifted cylinder still has the old sampled radial normals.
        let reference = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.25, y: 0, z: 0), axis: .unitZ, radius: 1))
        for t in [0.0, Double.pi, 2 * Double.pi] {
            let p = try Curve3D.circle(circle).point(at: t, tolerance: .standard)
            let n = try SurfaceFootResolver().foot(of: p, on: reference, tolerance: .standard).normal
            #expect(n.cross(p - circle.center).length <= ModelingTolerance.standard.angle)
        }
        #expect(throws: KernelError.self) {
            do {
                _ = try CurvedHingeDraftSurfaceBuilder(tolerance: .standard).surface(
                    hinge: .circle(circle), start: 0, end: 2 * .pi, reference: reference,
                    referenceSign: 1, outward: .unitZ, angle: .pi / 6, reach: 2)
            } catch let error as KernelError {
                #expect(error.code == .unsupportedCapability)
                throw error
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func equatorialSphereRetainsItsOriginalRadialAuthority() throws {
        let result = try CurvedHingeDraftSurfaceBuilder(tolerance: .standard).surface(
            hinge: .circle(Circle3D(center: .origin, normal: .unitZ, radius: 2)),
            start: 0, end: .pi, reference: .analytic(.sphere(center: .origin, radius: 2)),
            referenceSign: 1, outward: .unitZ, angle: .pi / 4, reach: 4)
        guard case let .analytic(.cone(apex, _, halfAngle)) = result else {
            Issue.record("An original equatorial sphere must produce its exact cone.")
            return
        }
        #expect((apex - Point3D(x: 0, y: 0, z: 2)).length <= 1e-12)
        #expect(abs(halfAngle - .pi / 4) <= 1e-12)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["retained", "hiddenExcursion", "movedEndpoint"])
    func replacementDispatchUsesWholeOriginalTrim(mode: String) throws {
        let hasHiddenExcursion = mode == "hiddenExcursion"
        let movesEndpoint = mode == "movedEndpoint"
        let controls = (0...16).map { index in
            Point3D(x: Double(index) / 16, y: 0,
                    z: movesEndpoint ? Double(index) / 16 : (hasHiddenExcursion && index % 2 == 1 ? 0.1 : 0))
        }
        let knots = [0.0] + (0...16).map { Double($0) / 16 } + [1.0]
        let original = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: knots, controlPoints: controls))
        for index in 0...8 {
            let expectedZ = movesEndpoint ? Double(index) / 8 : 0
            #expect(abs(try original.point(at: Double(index) / 8, tolerance: .standard).z - expectedZ) <= 1e-12)
        }
        #expect(abs(try original.point(at: 1.0 / 16, tolerance: .standard).z)
                == (movesEndpoint ? 1.0 / 16 : (hasHiddenExcursion ? 0.1 : 0)))
        let start = Vertex(point: .origin)
        let end = Vertex(point: Point3D(x: 1, y: 0, z: movesEndpoint ? 1 : 0))
        let curveID = CurveID()
        let edge = Edge(curveID: curveID, startVertexID: start.id, endVertexID: end.id,
                        trim: CurveTrim(startParameter: 0, endParameter: 1))
        // A minimal owner graph isolates the production edge dispatch and vertex anchors.
        // It is not asserted to be a closed volumetric BRep fixture.
        let firstLoop = Loop(edges: [Coedge(edgeID: edge.id)])
        let secondLoop = Loop(edges: [Coedge(edgeID: edge.id, orientation: .reversed)])
        let firstSurfaceID = SurfaceID(), secondSurfaceID = SurfaceID()
        let firstFace = Face(surfaceID: firstSurfaceID, loops: [firstLoop.id])
        let secondFace = Face(surfaceID: secondSurfaceID, loops: [secondLoop.id])
        let shell = Shell(faceIDs: [firstFace.id, secondFace.id])
        let body = Body(sheetShellIDs: [shell.id])
        let replacement = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let originalSurface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: knots, vKnots: [0, 0, 1, 1],
            controlPoints: [controls, controls.map { $0 + Vector3D.unitY }]))
        var model = BRepModel(
            geometry: GeometryStore(curves: [curveID: original], surfaces: [
                firstSurfaceID: originalSurface,
                secondSurfaceID: .plane(Plane3D(origin: .origin, normal: .unitY))]),
            bodies: [body.id: body], shells: [shell.id: shell],
            faces: [firstFace.id: firstFace, secondFace.id: secondFace],
            loops: [firstLoop.id: firstLoop, secondLoop.id: secondLoop], edges: [edge.id: edge],
            vertices: [start.id: start, end.id: end])
        try FaceSurfaceReplacementRebuilder().replace(
            [firstFace.id: .init(surface: replacement, orientation: .forward)],
            bodyID: body.id, featureID: FeatureID(), model: &model, tolerance: .standard,
            knownPoints: [start.id: start.point, end.id: Point3D(x: 1, y: 0, z: 0)])
        let solvedEdge = try #require(model.edges[edge.id])
        let solved = try #require(model.geometry.curves[solvedEdge.curveID])
        if hasHiddenExcursion || movesEndpoint {
            #expect(solved != original)
            #expect(abs(try solved.point(at: 1.0 / 16, tolerance: .standard).z) <= 1e-12)
            #expect(solved.hasExactLinearParameterization)
        } else {
            #expect(solved == original)
        }
    }
}
