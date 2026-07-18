import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive cone-torus Boolean integration")
struct PrimitiveConeTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactTorusSegment() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: overlapVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactTorusRemainder() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: torusVolume() - overlapVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactMergedBody() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: coneVolume() + torusVolume() - overlapVolume()
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let torusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Torus"
        )
        let coneID = try builder.cone(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: -3.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            baseRadius: length(6.0),
            height: length(6.0),
            named: "Cone"
        )
        let booleanID = try builder.boolean(
            targets: [torusID],
            tool: coneID,
            operation: operation,
            named: "Exact cone-torus Boolean"
        )
        let document = try builder.build(name: "Cone-torus Boolean")
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
        let volumeTolerance = ModelingTolerance.standard.distance * 6.0 * 6.0 * 64.0
        #expect(abs(volume - expectedVolume) <= volumeTolerance)
        let booleanLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(booleanLineage.isEmpty == false)
        #expect(booleanLineage.contains { $0.parents.isEmpty == false })
    }

    private func overlapVolume() -> Double {
        3.0 * Double.pi * Double.pi - 4.0 * Double.pi / (3.0 * sqrt(2.0))
    }

    private func torusVolume() -> Double {
        6.0 * Double.pi * Double.pi
    }

    private func coneVolume() -> Double {
        72.0 * Double.pi
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
