import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive general torus-torus Boolean integration", .serialized)
struct PrimitiveGeneralTorusTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(5)))
    func intersectionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 8.810_3
        )
    }

    @Test(.timeLimit(.minutes(5)))
    func differenceProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 50.407_326_406_536_15
        )
    }

    @Test(.timeLimit(.minutes(5)))
    func unionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 83.292_848_270_965_88
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        let tolerance = ModelingTolerance.standard
        let axis = try Vector3D(x: 0.25, y: 0.1, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let referenceDirection = try axis.cross(.unitY).normalized(
            tolerance: tolerance.distance
        )
        var builder = DocumentBuilder(units: .meters, tolerance: tolerance)
        let firstTorusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Reference torus"
        )
        let secondTorusID = try builder.torus(
            placement: PrimitivePlacement(
                origin: Point3D(x: 1.2, y: 0.2, z: 0.5),
                axis: axis,
                referenceDirection: referenceDirection
            ),
            majorRadius: length(3.4),
            minorRadius: length(0.7),
            named: "Tilted offset torus"
        )
        let booleanID = try builder.boolean(
            targets: [firstTorusID],
            tool: secondTorusID,
            operation: operation,
            named: "Exact general torus-torus Boolean"
        )
        let builderDocument = try builder.build(
            name: "General torus-torus Boolean"
        )
        let document = try replayCodableCommands(from: builderDocument)
        #expect(
            try document.sourceFingerprint(tolerance: tolerance)
                == builderDocument.sourceFingerprint(tolerance: tolerance)
        )
        let evaluated = try DocumentEvaluator(
            tolerance: tolerance,
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
        let volumeTolerance = ModelingTolerance.standard.distance
            * 4.1 * 4.1 * 128.0
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
