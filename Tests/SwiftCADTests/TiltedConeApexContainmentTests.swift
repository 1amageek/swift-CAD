import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
import SwiftCAD

// Regression coverage for the cone-apex chart singularity: loop-polygon
// samples at the apex project to an arbitrary u, and straight slant edges
// would otherwise draw a diagonal through the face interior, making
// quadrant faces claim each other's regions.
@Suite("Tilted cone apex containment")
struct TiltedConeApexContainmentTests {
    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    @Test(.timeLimit(.minutes(1)))
    func quadrantTwoCurvePointsBelongToQuadrantTwoFace() throws {
        let tolerance = ModelingTolerance.standard
        let axis = try Vector3D(x: 0.05, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let referenceDirection = try axis.cross(.unitY).normalized(
            tolerance: tolerance.distance
        )
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try builder.cone(
            placement: PrimitivePlacement(
                origin: .origin,
                axis: axis,
                referenceDirection: referenceDirection
            ),
            baseRadius: length(12.0),
            height: length(2.0),
            named: "Tilted wide cone"
        )
        let document = try builder.build(name: "Tilted cone")
        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        let model = evaluated.brep

        let halfAngleCosine = 2.0 / (4.0 + 144.0).squareRoot()

        // Solve for torus points that also satisfy the cone constraint:
        // p(theta, phi) on the torus (major 3, minor 1) with
        // dot(p, axis) / |p| == cos(halfAngle).
        func conePoint(theta: Double) -> Point3D {
            func deviation(_ phi: Double) -> Double {
                let rho = 3.0 + cos(phi)
                let point = Vector3D(
                    x: rho * cos(theta),
                    y: rho * sin(theta),
                    z: sin(phi)
                )
                return point.dot(axis) / point.length - halfAngleCosine
            }
            var lower = 0.0
            var upper = Double.pi / 2.0
            precondition(deviation(lower) * deviation(upper) < 0.0)
            for _ in 0..<80 {
                let middle = (lower + upper) * 0.5
                if deviation(lower) * deviation(middle) <= 0.0 {
                    upper = middle
                } else {
                    lower = middle
                }
            }
            let phi = (lower + upper) * 0.5
            let rho = 3.0 + cos(phi)
            return Point3D(x: rho * cos(theta), y: rho * sin(theta), z: sin(phi))
        }

        var lateralFaces: [FaceID] = []
        for faceID in model.faces.keys.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                continue
            }
            if case .plane = surface { continue }
            if case .analytic(.plane) = surface { continue }
            lateralFaces.append(faceID)
        }

        func loopCorners(_ faceID: FaceID) -> [Point3D] {
            guard let face = model.faces[faceID] else { return [] }
            var corners: [Point3D] = []
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { continue }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID],
                          let end = model.vertices[edge.endVertexID] else {
                        continue
                    }
                    corners.append(start.point)
                    corners.append(end.point)
                }
            }
            return corners
        }

        // Quadrant II face: loop corners include the base points near
        // (-11.885, 0, 2.597) and (0.0999, 12, 1.9975).
        func matches(_ faceID: FaceID, _ targets: [Point3D]) -> Bool {
            let corners = loopCorners(faceID)
            return targets.allSatisfy { target in
                corners.contains { corner in
                    corner.isApproximatelyEqual(to: target, tolerance: 1.0e-3)
                }
            }
        }
        let baseMinusX = Point3D(x: -11.885152832646353, y: 0.0, z: 2.596756081082395)
        let basePlusY = Point3D(x: 0.09987523388778735, y: 12.0, z: 1.997504677755688)
        let baseMinusY = Point3D(x: 0.09987523388778294, y: -12.0, z: 1.9975046777556882)
        guard let quadrantTwoFace = lateralFaces.first(where: {
            matches($0, [baseMinusX, basePlusY])
        }), let quadrantThreeFace = lateralFaces.first(where: {
            matches($0, [baseMinusX, baseMinusY])
        }) else {
            Issue.record("Could not identify quadrant faces among \(lateralFaces.count) lateral faces")
            return
        }

        let containment = DefaultFacePointContainmentTester()
        for degrees in [110.0, 120.0, 125.0, 130.0, 135.0, 140.0, 150.0, 160.0] {
            let theta = degrees * Double.pi / 180.0
            let point = conePoint(theta: theta)
            let inQ2 = try containment.contains(
                point,
                on: quadrantTwoFace,
                in: model,
                tolerance: tolerance
            )
            let inQ3 = try containment.contains(
                point,
                on: quadrantThreeFace,
                in: model,
                tolerance: tolerance
            )
            #expect(inQ2 == true, "theta=\(degrees) should be inside the quadrant II face")
            #expect(inQ3 == false, "theta=\(degrees) should be outside the quadrant III face")
        }
    }
}
