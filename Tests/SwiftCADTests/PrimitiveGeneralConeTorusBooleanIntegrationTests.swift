import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive general cone-torus Boolean integration", .serialized)
struct PrimitiveGeneralConeTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(10)))
    func intersectionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 11.489_854_194_529_729
        )
    }

    @Test(.timeLimit(.minutes(10)))
    func differenceProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 47.727_772_212_006_42
        )
    }

    @Test(.timeLimit(.minutes(10)))
    func unionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 349.320_666_956_626_55
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        let axis = try Vector3D(x: 0.05, y: 0.0, z: 1.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        let referenceDirection = try axis.cross(.unitY).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let torusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Torus"
        )
        let coneID = try builder.cone(
            placement: PrimitivePlacement(
                origin: .origin,
                axis: axis,
                referenceDirection: referenceDirection
            ),
            baseRadius: length(12.0),
            height: length(2.0),
            named: "Tilted wide cone"
        )
        let booleanID = try builder.boolean(
            targets: [torusID],
            tool: coneID,
            operation: operation,
            named: "Exact general cone-torus Boolean"
        )
        let builderDocument = try builder.build(name: "General cone-torus Boolean")
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
        let volumeTolerance = ModelingTolerance.standard.distance * 12.0 * 12.0 * 8.0
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
