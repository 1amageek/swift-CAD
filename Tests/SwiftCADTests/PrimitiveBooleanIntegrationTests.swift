import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive Boolean integration", .serialized)
struct PrimitiveBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func offsetSphereCylinderIntersectionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 36.773_553_242_333_68
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetSphereCylinderDifferenceProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 76.323_782_286_898_88
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetSphereCylinderUnionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 132.872_450_051_515_16
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
                origin: Point3D(x: 1.0, y: 0.0, z: -4.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(1.5),
            height: length(8.0),
            named: "Offset cylinder"
        )
        let booleanID = try builder.boolean(
            targets: [sphereID],
            tool: cylinderID,
            operation: operation,
            named: "Exact sphere-cylinder Boolean"
        )
        let builderDocument = try builder.build(name: "Primitive Boolean")
        let document = try replayCodableCommands(from: builderDocument)

        #expect(try document.sourceFingerprint(tolerance: .standard) == builderDocument.sourceFingerprint(tolerance: .standard))

        return (
            try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document),
            booleanID
        )
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

    private func replayCodableCommands(from source: CADDocument) throws -> CADDocument {
        let editor = DocumentEditor()
        var result = CADDocument(
            units: source.units,
            metadata: source.metadata
        )
        for featureID in source.designGraph.order {
            let node = try #require(source.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(CADCommand.self, from: encoded)
            #expect(decoded == command)
            result = try editor.apply(decoded, to: result, tolerance: .standard)
        }
        return result
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
