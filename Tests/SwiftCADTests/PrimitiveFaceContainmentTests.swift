import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
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
