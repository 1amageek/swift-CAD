import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive cone Boolean integration")
struct PrimitiveConeBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactPiecewiseCone() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 20.0 * Double.pi
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactConeRemainder() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 4.0 * Double.pi / 3.0
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactMergedBody() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 260.0 * Double.pi / 3.0
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let targetID = try builder.cone(
            baseRadius: length(4.0),
            height: length(4.0),
            named: "Target cone"
        )
        let toolID = try builder.cone(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: 1.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            baseRadius: length(8.0),
            height: length(4.0),
            named: "Tool cone"
        )
        let booleanID = try builder.boolean(
            targets: [targetID],
            tool: toolID,
            operation: operation,
            named: "Exact cone Boolean"
        )
        let document = try builder.build(name: "Cone Boolean")
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

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
