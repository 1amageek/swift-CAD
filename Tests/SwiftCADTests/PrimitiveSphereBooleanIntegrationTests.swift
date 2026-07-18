import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive sphere Boolean integration")
struct PrimitiveSphereBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func offsetSphereIntersectionProducesValidatedExactLens() throws {
        let result = try evaluate(operation: .intersect)
        try assertExactResult(
            result,
            expectedVolume: 56.0 * Double.pi / 3.0
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetSphereDifferenceProducesValidatedExactRemainder() throws {
        let result = try evaluate(operation: .difference)
        try assertExactResult(
            result,
            expectedVolume: 52.0 * Double.pi / 3.0
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetSphereUnionProducesValidatedExactMergedBody() throws {
        let result = try evaluate(operation: .union)
        try assertExactResult(
            result,
            expectedVolume: 160.0 * Double.pi / 3.0
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let firstSphereID = try builder.sphere(
            radius: length(3.0),
            named: "First sphere"
        )
        let secondSphereID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.0),
            named: "Second sphere"
        )
        let booleanID = try builder.boolean(
            targets: [firstSphereID],
            tool: secondSphereID,
            operation: operation,
            named: "Exact sphere Boolean"
        )
        let document = try builder.build(name: "Sphere Boolean")
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
        let volumeTolerance = ModelingTolerance.standard.distance * 3.0 * 3.0 * 16.0
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
