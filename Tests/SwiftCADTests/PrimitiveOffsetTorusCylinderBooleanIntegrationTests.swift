import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive offset torus-cylinder Boolean integration", .serialized)
struct PrimitiveOffsetTorusCylinderBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func intersectionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 2.323_037_360_983_310_4
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func differenceProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 130.916_622_053_723_04
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func unionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 135.629_011_034_107_73
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let torusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.5),
            named: "Torus"
        )
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(
                origin: Point3D(x: 3.0, y: 0.0, z: -3.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(0.5),
            height: length(6.0),
            named: "Offset cylinder"
        )
        let booleanID = try builder.boolean(
            targets: [torusID],
            tool: cylinderID,
            operation: operation,
            named: "Exact offset torus-cylinder Boolean"
        )
        let builderDocument = try builder.build(name: "Offset torus-cylinder Boolean")
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
        try result.document.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.document.brep.bodies.count == 1)
        #expect(result.document.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        let volume = try result.document.brep.volume(tolerance: .standard)
        let volumeTolerance = ModelingTolerance.standard.distance * 6.0 * 6.0 * 64.0
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
