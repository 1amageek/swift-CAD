import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive general sphere-torus Boolean integration", .serialized)
struct PrimitiveGeneralSphereTorusBooleanIntegrationTests {
    @Test(.timeLimit(.minutes(5)))
    func intersectionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .intersect),
            expectedVolume: 23.330_574_601_640_733
        )
    }

    @Test(.timeLimit(.minutes(5)))
    func differenceProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .difference),
            expectedVolume: 89.766_760_927_591_82
        )
    }

    @Test(.timeLimit(.minutes(5)))
    func unionProducesValidatedExactBRep() throws {
        try assertExactResult(
            evaluate(operation: .union),
            expectedVolume: 148.984_387_334_127_98
        )
    }

    private func evaluate(
        operation: BooleanOperation
    ) throws -> (document: EvaluatedDocument, featureID: FeatureID) {
        let axis = try Vector3D(x: 0.2, y: 0.0, z: 1.0).normalized(
            tolerance: ModelingTolerance.standard.distance
        )
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sphereID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(
                    x: axis.x * 0.25,
                    y: 0.5,
                    z: axis.z * 0.25
                ),
                axis: .unitZ,
                referenceDirection: .unitX
            ),
            radius: length(3.0),
            named: "Offset sphere"
        )
        let torusID = try builder.torus(
            placement: PrimitivePlacement(
                origin: .origin,
                axis: axis,
                referenceDirection: .unitY
            ),
            majorRadius: length(3.0),
            minorRadius: length(1.0),
            named: "Torus"
        )
        let booleanID = try builder.boolean(
            targets: [sphereID],
            tool: torusID,
            operation: operation,
            named: "Exact general sphere-torus Boolean"
        )
        let builderDocument = try builder.build(name: "General sphere-torus Boolean")
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
        #expect(volume.isFinite)
        let volumeTolerance = ModelingTolerance.standard.distance * 4.0 * 4.0 * 64.0
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
