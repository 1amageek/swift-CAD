import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive torus-cylinder Boolean integration")
struct PrimitiveTorusCylinderBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactInnerTorusSegment() throws {
        let innerVolume = torusVolume(insideRadialCutoff: 0.5)
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: innerVolume
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactOuterTorusSegment() throws {
        let outerVolume = 6.0 * Double.pi * Double.pi
            - torusVolume(insideRadialCutoff: 0.5)
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: outerVolume
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactMergedBody() throws {
        let outerVolume = 6.0 * Double.pi * Double.pi
            - torusVolume(insideRadialCutoff: 0.5)
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 49.0 * Double.pi + outerVolume
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
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: -2.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.5),
            height: length(4.0),
            named: "Cylinder"
        )
        let booleanID = try builder.boolean(
            targets: [torusID],
            tool: cylinderID,
            operation: operation,
            named: "Exact torus-cylinder Boolean"
        )
        let document = try builder.build(name: "Torus-cylinder Boolean")
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

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private func torusVolume(insideRadialCutoff cutoff: Double) -> Double {
        let majorRadius = 3.0
        let minorRadius = 1.0
        let height = sqrt(minorRadius * minorRadius - cutoff * cutoff)
        let meridianArea = cutoff * height
            + minorRadius * minorRadius * (
                asin(cutoff / minorRadius) + Double.pi * 0.5
            )
        let radialFirstMoment = -2.0 * pow(height, 3.0) / 3.0
        return 2.0 * Double.pi * (
            majorRadius * meridianArea + radialFirstMoment
        )
    }
}
