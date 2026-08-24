import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
import SwiftCAD

@Suite("Primitive face containment")
struct PrimitiveFaceContainmentTests {
    @Test(.timeLimit(.minutes(1)))
    func curvedFacesCoverIntersectionSamplesWithoutGaps() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sphereID = try builder.sphere(
            radius: length(3.0),
            named: "Sphere"
        )
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(
                origin: Point3D(x: 1.0, y: 0.0, z: -4.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(1.5),
            height: length(8.0),
            named: "Offset cylinder"
        )
        let document = try builder.build(name: "Primitive Boolean operands")
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let sphereFaceIDs = faceIDs(for: sphereID, in: evaluated)
        let cylinderFaceIDs = faceIDs(for: cylinderID, in: evaluated).filter { faceID in
            guard let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else {
                return false
            }
            if case .cylinder = surface { return true }
            return false
        }
        let containment = DefaultFacePointContainmentTester()
        for index in 0..<8 {
            let angle = Double(index) * Double.pi * 0.25
            let x = 1.0 + 1.5 * cos(angle)
            let y = 1.5 * sin(angle)
            let z = sqrt(max(0.0, 9.0 - x * x - y * y))
            let point = Point3D(x: x, y: y, z: z)
            let sphereMatches = try sphereFaceIDs.filter {
                try containment.contains(
                    point,
                    on: $0,
                    in: evaluated.brep,
                    tolerance: evaluated.configuration.tolerance
                )
            }
            let cylinderMatches = try cylinderFaceIDs.filter {
                try containment.contains(
                    point,
                    on: $0,
                    in: evaluated.brep,
                    tolerance: evaluated.configuration.tolerance
                )
            }
            #expect(sphereMatches.isEmpty == false)
            #expect(cylinderMatches.isEmpty == false)
            if index.isMultiple(of: 2) == false {
                #expect(sphereMatches.count == 1)
                #expect(cylinderMatches.count == 1)
            }
        }
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private func faceIDs(
        for featureID: FeatureID,
        in evaluated: EvaluatedDocument
    ) -> [FaceID] {
        evaluated.subshapes.entries.compactMap { subshapeID, reference in
            guard subshapeID.featureID == featureID,
                  case let .face(faceID) = reference else {
                return nil
            }
            return faceID
        }.sorted()
    }
}

@Suite("Offset sphere octant containment")
struct OffsetSphereOctantContainmentTests {
    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    @Test(.timeLimit(.minutes(1)))
    func intersectionCircleStaysOutsideDisjointOctants() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try builder.sphere(radius: length(3.0), named: "Base")
        _ = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.0),
            named: "Offset"
        )
        let document = try builder.build(name: "Offset spheres")
        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        let containment = DefaultFacePointContainmentTester()
        // The intersection circle of the two spheres lies in the plane
        // x = 1, so every octant face of the offset sphere whose whole
        // region satisfies x >= 2 must reject each circle point.
        let circleCenter = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let circleRadius = (8.0).squareRoot()
        for faceID in evaluated.brep.faces.keys.sorted() {
            guard let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID],
                  case .analytic(.sphere(let center, _)) = surface,
                  center.isApproximatelyEqual(
                      to: Point3D(x: 2.0, y: 0.0, z: 0.0),
                      tolerance: 1.0e-9
                  ) else {
                continue
            }
            for sampleIndex in 0..<16 {
                let angle = Double(sampleIndex) * Double.pi / 8.0
                let point = Point3D(
                    x: circleCenter.x,
                    y: circleRadius * cos(angle),
                    z: circleRadius * sin(angle)
                )
                let contained = try containment.contains(
                    point,
                    on: faceID,
                    in: evaluated.brep,
                    tolerance: evaluated.configuration.tolerance
                )
                if contained {
                    // A face is a strictly x >= 2 octant only when every
                    // boundary edge midpoint lies behind the section plane;
                    // corner vertices alone can all sit on x = 2 for the
                    // opposite octant.
                    var midpoints: [Point3D] = []
                    for loopID in face.loops {
                        guard let loop = evaluated.brep.loops[loopID] else {
                            continue
                        }
                        for coedge in loop.edges {
                            guard let edge = evaluated.brep.edges[coedge.edgeID],
                                  let curve = evaluated.brep.geometry.curves[edge.curveID],
                                  let trim = edge.trim else {
                                continue
                            }
                            let middle = trim.startParameter
                                + (trim.endParameter - trim.startParameter) * 0.5
                            midpoints.append(try curve.point(
                                at: middle,
                                tolerance: evaluated.configuration.tolerance
                            ))
                        }
                    }
                    let allBehind = midpoints.isEmpty == false
                        && midpoints.allSatisfy { $0.x >= 2.0 - 1.0e-6 }
                    #expect(
                        allBehind == false,
                        "Face \(faceID) with midpoints \(midpoints) claims circle point \(point)"
                    )
                }
            }
        }
    }
}
