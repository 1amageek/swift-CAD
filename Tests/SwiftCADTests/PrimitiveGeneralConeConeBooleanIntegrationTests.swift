import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive general cone-cone Boolean integration", .serialized)
struct PrimitiveGeneralConeConeBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func intersectionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 1.182_403_556_345_02
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func differenceProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 132.858_882_996_819_5
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func unionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 142.283_660_957_588_86
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let targetID = try builder.cone(
            baseRadius: length(4.0),
            height: length(8.0),
            named: "Target cone"
        )
        let toolID = try builder.cone(
            placement: PrimitivePlacement(
                origin: Point3D(x: 0.0, y: 0.0, z: 4.0),
                axis: .unitY,
                referenceDirection: .unitX
            ),
            baseRadius: length(1.5),
            height: length(4.0),
            named: "Transverse cone"
        )
        let booleanID = try builder.boolean(
            targets: [targetID],
            tool: toolID,
            operation: operation,
            named: "Exact general cone-cone Boolean"
        )
        let builderDocument = try builder.build(name: "General cone-cone Boolean")
        let document = try replayCodableCommands(from: builderDocument)
        #expect(
            try document.sourceFingerprint(tolerance: .standard)
                == builderDocument.sourceFingerprint(tolerance: .standard)
        )
        let evaluated = try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(document)
        return (evaluated, booleanID)
    }

    private func assertExactResult(
        _ result: (document: EvaluatedDocument, featureID: FeatureID),
        expectedVolume: Double
    ) throws {
        try result.document.brep.validate(level: .exact, tolerance: .standard)
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
