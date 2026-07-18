import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive sphere-torus Boolean integration")
struct PrimitiveSphereTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactRevolvedLens() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: intersectionVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactSphereRemainder() throws {
        let sphereVolume = 4.0 * Double.pi * pow(3.5, 3.0) / 3.0
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: sphereVolume - intersectionVolume()
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactMergedBody() throws {
        let sphereVolume = 4.0 * Double.pi * pow(3.5, 3.0) / 3.0
        let torusVolume = 6.0 * Double.pi * Double.pi
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: sphereVolume + torusVolume - intersectionVolume()
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sphereID = try builder.sphere(
            radius: length(3.5),
            named: "Sphere"
        )
        let torusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Torus"
        )
        let booleanID = try builder.boolean(
            targets: [sphereID],
            tool: torusID,
            operation: operation,
            named: "Exact sphere-torus Boolean"
        )
        let document = try builder.build(name: "Sphere-torus Boolean")
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

    private func intersectionVolume() -> Double {
        let sphereRadius = 3.5
        let torusMajorRadius = 3.0
        let torusMinorRadius = 1.0
        let radialIntersection = (
            sphereRadius * sphereRadius
                - torusMinorRadius * torusMinorRadius
                + torusMajorRadius * torusMajorRadius
        ) / (2.0 * torusMajorRadius)
        let torusLowerRadius = torusMajorRadius - torusMinorRadius
        return 2.0 * Double.pi * (
            circleRadialMomentPrimitive(
                at: radialIntersection,
                centerRadius: torusMajorRadius,
                circleRadius: torusMinorRadius
            ) - circleRadialMomentPrimitive(
                at: torusLowerRadius,
                centerRadius: torusMajorRadius,
                circleRadius: torusMinorRadius
            ) + circleRadialMomentPrimitive(
                at: sphereRadius,
                centerRadius: 0.0,
                circleRadius: sphereRadius
            ) - circleRadialMomentPrimitive(
                at: radialIntersection,
                centerRadius: 0.0,
                circleRadius: sphereRadius
            )
        )
    }

    private func circleRadialMomentPrimitive(
        at radius: Double,
        centerRadius: Double,
        circleRadius: Double
    ) -> Double {
        let centered = radius - centerRadius
        let height = sqrt(max(0.0, circleRadius * circleRadius - centered * centered))
        return -2.0 * pow(height, 3.0) / 3.0
            + centerRadius * (
                centered * height
                    + circleRadius * circleRadius * asin(centered / circleRadius)
            )
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
