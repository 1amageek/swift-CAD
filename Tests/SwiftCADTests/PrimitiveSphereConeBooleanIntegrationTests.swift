import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive sphere-cone Boolean integration")
struct PrimitiveSphereConeBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func coaxialIntersectionProducesValidatedExactBRep() throws {
        let intersectionVolume = sphereConeIntersectionVolume(
            sphereRadius: 3.0,
            coneApexZ: -4.0,
            coneSlope: 0.5
        )
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: intersectionVolume
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialDifferenceProducesValidatedExactBRep() throws {
        let sphereVolume = 36.0 * Double.pi
        let intersectionVolume = sphereConeIntersectionVolume(
            sphereRadius: 3.0,
            coneApexZ: -4.0,
            coneSlope: 0.5
        )
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: sphereVolume - intersectionVolume
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coaxialUnionProducesValidatedExactBRep() throws {
        let sphereVolume = 36.0 * Double.pi
        let coneVolume = 128.0 * Double.pi / 3.0
        let intersectionVolume = sphereConeIntersectionVolume(
            sphereRadius: 3.0,
            coneApexZ: -4.0,
            coneSlope: 0.5
        )
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: sphereVolume + coneVolume - intersectionVolume
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
        let coneID = try builder.cone(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: -4.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            baseRadius: length(4.0),
            height: length(8.0),
            named: "Cone"
        )
        let booleanID = try builder.boolean(
            targets: [sphereID],
            tool: coneID,
            operation: operation,
            named: "Exact sphere-cone Boolean"
        )
        let document = try builder.build(name: "Sphere-cone Boolean")
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
        let volumeTolerance = ModelingTolerance.standard.distance * 3.0 * 3.0 * 32.0
        #expect(abs(volume - expectedVolume) <= volumeTolerance)
        let booleanLineage = result.document.lineage.values.filter {
            $0.output.featureID == result.featureID
        }
        #expect(booleanLineage.isEmpty == false)
        #expect(booleanLineage.contains { $0.parents.isEmpty == false })
    }

    private func sphereConeIntersectionVolume(
        sphereRadius: Double,
        coneApexZ: Double,
        coneSlope: Double
    ) -> Double {
        let slopeSquared = coneSlope * coneSlope
        let a = 1.0 + slopeSquared
        let b = -2.0 * slopeSquared * coneApexZ
        let c = slopeSquared * coneApexZ * coneApexZ
            - sphereRadius * sphereRadius
        let discriminant = b * b - 4.0 * a * c
        let lower = (-b - sqrt(discriminant)) / (2.0 * a)
        let upper = (-b + sqrt(discriminant)) / (2.0 * a)
        return spherePrimitive(
            at: lower,
            radius: sphereRadius
        ) - spherePrimitive(
            at: -sphereRadius,
            radius: sphereRadius
        ) + conePrimitive(
            at: upper,
            apexZ: coneApexZ,
            slopeSquared: slopeSquared
        ) - conePrimitive(
            at: lower,
            apexZ: coneApexZ,
            slopeSquared: slopeSquared
        ) + spherePrimitive(
            at: sphereRadius,
            radius: sphereRadius
        ) - spherePrimitive(
            at: upper,
            radius: sphereRadius
        )
    }

    private func spherePrimitive(at z: Double, radius: Double) -> Double {
        Double.pi * (radius * radius * z - z * z * z / 3.0)
    }

    private func conePrimitive(
        at z: Double,
        apexZ: Double,
        slopeSquared: Double
    ) -> Double {
        Double.pi * slopeSquared * pow(z - apexZ, 3.0) / 3.0
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
