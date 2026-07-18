import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive general cone-cylinder Boolean integration", .serialized)
struct PrimitiveGeneralConeCylinderBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func transverseCylinderIntersectionProducesValidatedExactSolid() throws {
        try assertExactResult(evaluate(operation: .intersect))
    }

    @Test(.timeLimit(.minutes(1)))
    func transverseCylinderDifferenceProducesValidatedExactSolid() throws {
        try assertExactResult(evaluate(operation: .difference))
    }

    @Test(.timeLimit(.minutes(1)))
    func transverseCylinderUnionProducesValidatedExactSolid() throws {
        try assertExactResult(evaluate(operation: .union))
    }

    @Test(.timeLimit(.minutes(1)))
    func transverseCylinderWithHyperbolicCapSectionsProducesValidatedIntersection() throws {
        try assertExactResult(evaluate(
            operation: .intersect,
            cylinderMinimumY: -3.0,
            cylinderHeight: 6.0
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func transverseCylinderWithHyperbolicCapSectionsProducesValidatedDifference() throws {
        try assertExactResult(evaluate(
            operation: .difference,
            cylinderMinimumY: -3.0,
            cylinderHeight: 6.0
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func transverseCylinderWithHyperbolicCapSectionsProducesValidatedUnion() throws {
        try assertExactResult(evaluate(
            operation: .union,
            cylinderMinimumY: -3.0,
            cylinderHeight: 6.0
        ))
    }

    private func evaluate(
        operation: BooleanOperation,
        cylinderMinimumY: Double = -5.0,
        cylinderHeight: Double = 10.0
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let coneID = try builder.cone(
            baseRadius: length(4.0),
            height: length(8.0),
            named: "Cone"
        )
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: cylinderMinimumY, z: 4.0),
                axis: .unitY,
                referenceDirection: .unitX
            ),
            radius: length(1.0),
            height: length(cylinderHeight),
            named: "Transverse cylinder"
        )
        let booleanID = try builder.boolean(
            targets: [coneID],
            tool: cylinderID,
            operation: operation,
            named: "General cone-cylinder Boolean"
        )
        let document = try builder.build(name: "General cone-cylinder Boolean")

        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        return (evaluated, booleanID)
    }

    private func assertExactResult(
        _ result: (document: EvaluatedDocument, featureID: FeatureID)
    ) throws {
        try result.document.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.document.brep.bodies.count == 1)
        #expect(try result.document.brep.volume(tolerance: .standard) > 0.0)
        let outputLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(outputLineage.isEmpty == false)
        #expect(outputLineage.contains { $0.parents.isEmpty == false })
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
