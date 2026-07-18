import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive offset torus-torus Boolean integration", .serialized)
struct PrimitiveOffsetTorusTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func intersectionProducesOneValidatedExactBody() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedBodyCount: 1,
            expectedVolume: 7.285_038_823_821_337
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func differenceProducesOneValidatedExactBody() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedBodyCount: 1,
            expectedVolume: 7.519_367_777_812_701
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func unionProducesOneValidatedExactBody() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedBodyCount: 1,
            expectedVolume: 140.759_027_192_519_04
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        let axis = try Vector3D(x: 0.2, y: 0.0, z: 1.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let firstTorusID = try builder.torus(
            placement: PrimitivePlacement(
                origin: .origin,
                axis: axis,
                referenceDirection: .unitY
            ),
            majorRadius: length(3.0),
            minorRadius: length(0.5),
            named: "Thin torus"
        )
        let secondTorusID = try builder.torus(
            placement: PrimitivePlacement(
                origin: Point3D(
                    x: axis.x * 0.25,
                    y: 2.2,
                    z: axis.z * 0.25
                ),
                axis: axis,
                referenceDirection: .unitY
            ),
            majorRadius: length(3.0),
            minorRadius: length(1.5),
            named: "Offset thick torus"
        )
        let booleanID = try builder.boolean(
            targets: [firstTorusID],
            tool: secondTorusID,
            operation: operation,
            named: "Exact offset torus-torus Boolean"
        )
        let builderDocument = try builder.build(name: "Offset torus-torus Boolean")
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
        expectedBodyCount: Int,
        expectedVolume: Double
    ) throws {
        try result.document.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.document.brep.bodies.count == expectedBodyCount)
        #expect(result.document.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        let volume = try result.document.brep.volume(tolerance: .standard)
        let volumeTolerance = ModelingTolerance.standard.distance * 4.5 * 4.5 * 64.0
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
