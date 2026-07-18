import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive sphere-cylinder Boolean integration")
struct PrimitiveSphereCylinderBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactCylinderSegment() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: overlapVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactSphereRemainder() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 36.0 * Double.pi - overlapVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactMergedBody() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 68.0 * Double.pi - overlapVolume()
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sphereID = try builder.sphere(
            radius: length(3.0),
            named: "Sphere"
        )
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: -4.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(2.0),
            height: length(8.0),
            named: "Cylinder"
        )
        let booleanID = try builder.boolean(
            targets: [sphereID],
            tool: cylinderID,
            operation: operation,
            named: "Exact sphere-cylinder Boolean"
        )
        let document = try builder.build(name: "Sphere-cylinder Boolean")
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        return (evaluated, booleanID)
    }

    private func assertExactResult(
        _ result: (document: EvaluatedDocument, featureID: FeatureID),
        expectedVolume: Double
    ) throws {
        try result.document.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.document.brep.bodies.count == 1)
        let volume = try result.document.brep.volume(tolerance: .standard)
        let volumeTolerance = ModelingTolerance.standard.distance * 8.0 * 8.0 * 64.0
        #expect(abs(volume - expectedVolume) <= volumeTolerance)
        let booleanLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(booleanLineage.isEmpty == false)
        #expect(booleanLineage.contains { $0.parents.isEmpty == false })
    }

    private func overlapVolume() -> Double {
        4.0 * Double.pi / 3.0 * (27.0 - 5.0 * sqrt(5.0))
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
