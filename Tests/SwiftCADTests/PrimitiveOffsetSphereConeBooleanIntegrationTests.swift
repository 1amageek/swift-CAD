import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive offset sphere-cone Boolean integration", .serialized)
struct PrimitiveOffsetSphereConeBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func intersectionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 56.319_383_462_815_27
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func differenceProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 56.777_952_066_417_29
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func unionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 190.819_238_619_581_8
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
                origin: Point3D(x: 1.0, y: 0.0, z: -4.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            baseRadius: length(4.0),
            height: length(8.0),
            named: "Offset cone"
        )
        let booleanID = try builder.boolean(
            targets: [sphereID],
            tool: coneID,
            operation: operation,
            named: "Exact offset sphere-cone Boolean"
        )
        let builderDocument = try builder.build(name: "Offset sphere-cone Boolean")
        let document = try replayCodableCommands(from: builderDocument)
        #expect(
            try document.sourceFingerprint(tolerance: .standard)
                == builderDocument.sourceFingerprint(tolerance: .standard)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        return (evaluated, booleanID)
    }

    private func assertExactResult(
        _ result: (document: EvaluatedDocument, featureID: FeatureID),
        expectedVolume: Double
    ) throws {
        #expect(result.document.brep.bodies.count == 1)
        #expect(result.document.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
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
