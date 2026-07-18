import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive torus Boolean integration")
struct PrimitiveTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactRevolvedLens() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: intersectionVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactTorusRemainder() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: torusVolume() - intersectionVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactMergedBody() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 2.0 * torusVolume() - intersectionVolume()
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let firstTorusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "First torus"
        )
        let secondTorusID = try builder.torus(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: 1.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Second torus"
        )
        let booleanID = try builder.boolean(
            targets: [firstTorusID],
            tool: secondTorusID,
            operation: operation,
            named: "Exact torus Boolean"
        )
        let document = try builder.build(name: "Torus Boolean")
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
        let volumeTolerance = ModelingTolerance.standard.distance * 4.0 * 4.0 * 64.0
        #expect(abs(volume - expectedVolume) <= volumeTolerance)
        let booleanLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(booleanLineage.isEmpty == false)
        #expect(booleanLineage.contains { $0.parents.isEmpty == false })
    }

    private func torusVolume() -> Double {
        6.0 * Double.pi * Double.pi
    }

    private func intersectionVolume() -> Double {
        let meridianLensArea = 2.0 * Double.pi / 3.0 - sqrt(3.0) * 0.5
        return 6.0 * Double.pi * meridianLensArea
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
