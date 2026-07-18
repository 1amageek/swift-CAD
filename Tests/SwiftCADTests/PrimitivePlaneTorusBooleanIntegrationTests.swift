import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive plane-torus Boolean integration", .serialized)
struct PrimitivePlaneTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func intersectionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 5.148_321_936_771_426
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func differenceProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 54.069_304_469_764_73
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func unionProducesValidatedExactSolid() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 134.069_304_469_764_73
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        let tolerance = ModelingTolerance.standard
        var builder = DocumentBuilder(units: .meters, tolerance: tolerance)
        let torusID = try builder.torus(
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Torus"
        )
        let boxID = try builder.box(
            placement: PrimitivePlacement(
                origin: Point3D(x: 3.0, y: -5.0, z: -2.0),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            width: length(2.0),
            depth: length(10.0),
            height: length(4.0),
            named: "Planar cutter"
        )
        let booleanID = try builder.boolean(
            targets: [torusID],
            tool: boxID,
            operation: operation,
            named: "Exact plane-torus Boolean"
        )
        let builderDocument = try builder.build(name: "Plane-torus Boolean")
        let replayedDocument = try replayCodableCommands(from: builderDocument)
        #expect(
            try replayedDocument.sourceFingerprint(tolerance: tolerance)
                == builderDocument.sourceFingerprint(tolerance: tolerance)
        )
        let evaluated = try DocumentEvaluator(
            tolerance: tolerance,
            artifactPolicy: .deferred
        ).evaluate(replayedDocument)
        return (evaluated, booleanID)
    }

    private func assertExactResult(
        _ result: (document: EvaluatedDocument, featureID: FeatureID),
        expectedVolume: Double
    ) throws {
        let tolerance = ModelingTolerance.standard
        try result.document.brep.validate(level: .exact, tolerance: tolerance)
        #expect(result.document.brep.bodies.count == 1)
        #expect(result.document.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        let volume = try result.document.brep.volume(tolerance: tolerance)
        let volumeTolerance = tolerance.distance * 10.0 * 10.0 * 128.0
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
