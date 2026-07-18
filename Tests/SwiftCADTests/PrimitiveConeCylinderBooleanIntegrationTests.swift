import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive cone-cylinder Boolean integration")
struct PrimitiveConeCylinderBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactPiecewiseRevolvedSolid() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 27.0 * Double.pi
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactConeRemainder() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 44.0 * Double.pi / 3.0
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactMergedBody() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 233.0 * Double.pi / 3.0
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let coneID = try builder.cone(
            baseRadius: length(5.0),
            height: length(5.0),
            named: "Cone"
        )
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: -1.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.0),
            height: length(7.0),
            named: "Cylinder"
        )
        let booleanID = try builder.boolean(
            targets: [coneID],
            tool: cylinderID,
            operation: operation,
            named: "Exact cone-cylinder Boolean"
        )
        let document = try builder.build(name: "Cone-cylinder Boolean")
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
        let volumeTolerance = ModelingTolerance.standard.distance * 7.0 * 7.0 * 64.0
        #expect(abs(volume - expectedVolume) <= volumeTolerance)
        let booleanLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(booleanLineage.isEmpty == false)
        #expect(booleanLineage.contains { $0.parents.isEmpty == false })
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
