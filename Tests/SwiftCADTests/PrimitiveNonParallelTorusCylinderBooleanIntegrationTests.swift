import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive non-parallel torus-cylinder Boolean integration", .serialized)
struct PrimitiveNonParallelTorusCylinderBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func intersectionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 25.600_248_236_765_488
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func differenceProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 33.617_378_169_770_66
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func unionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 316.360_716_992_852_1
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        let tolerance = ModelingTolerance.standard
        let axis = try Vector3D(x: 0.08, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let torusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Torus"
        )
        let cylinderID = try builder.cylinder(
            placement: PrimitivePlacement(
                origin: Point3D(
                    x: -axis.x * 5.0,
                    y: -axis.y * 5.0,
                    z: -axis.z * 5.0
                ),
                axis: axis,
                referenceDirection: .unitY
            ),
            radius: length(3.0),
            height: length(10.0),
            named: "Tilted cylinder"
        )
        let booleanID = try builder.boolean(
            targets: [torusID],
            tool: cylinderID,
            operation: operation,
            named: "Exact non-parallel torus-cylinder Boolean"
        )
        let builderDocument = try builder.build(
            name: "Non-parallel torus-cylinder Boolean"
        )
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
        let volumeTolerance = ModelingTolerance.standard.distance * 10.0 * 10.0 * 64.0
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
