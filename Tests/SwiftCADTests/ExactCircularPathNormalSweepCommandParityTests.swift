import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
import SwiftCAD

@Suite("Exact circular path-normal Sweep command parity")
struct ExactCircularPathNormalSweepCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalExactRevolve() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-8,
            angle: 1.0e-10
        )
        var builder = DocumentBuilder(
            units: .meters,
            tolerance: tolerance
        )
        let profile = try builder.sketch(on: .xy, named: "Sweep profile") { sketch in
            sketch.rectangle(
                width: .constant(.length(0.04, unit: .meter)),
                height: .constant(.length(0.02, unit: .meter))
            )
        }
        let path = try builder.sketch(on: .yz, named: "Circular normal path") { sketch in
            sketch.arc(
                center: point(-0.06, 0.0),
                radius: .constant(.length(0.06, unit: .meter)),
                startAngle: .constant(.angle(0.0, unit: .radian)),
                endAngle: .constant(.angle(0.5 * Double.pi, unit: .radian))
            )
        }
        let sweepFeatureID = try builder.sweep(
            profile,
            along: path.featureID,
            options: SweepOptions(alignment: .normal),
            named: "Exact circular path-normal Sweep"
        )
        let builderDocument = try builder.build(
            name: "Exact circular path-normal Sweep parity"
        )

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(
                name: "Exact circular path-normal Sweep parity"
            )
        )
        let editor = DocumentEditor()
        for featureID in builderDocument.designGraph.order {
            let node = try #require(
                builderDocument.designGraph.nodes[featureID]
            )
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let encodedCommand = try JSONEncoder().encode(command)
            let decodedCommand = try JSONDecoder().decode(
                CADCommand.self,
                from: encodedCommand
            )
            #expect(decodedCommand == command)
            commandDocument = try editor.apply(
                decodedCommand,
                to: commandDocument,
                tolerance: tolerance
            )
        }

        let encodedDocument = try JSONEncoder().encode(commandDocument)
        let persistedDocument = try JSONDecoder().decode(
            CADDocument.self,
            from: encodedDocument
        )
        #expect(try builderDocument.sourceFingerprint(tolerance: tolerance)
            == commandDocument.sourceFingerprint(tolerance: tolerance))
        #expect(try commandDocument.sourceFingerprint(tolerance: tolerance)
            == persistedDocument.sourceFingerprint(tolerance: tolerance))

        let evaluator = DocumentEvaluator(
            tolerance: tolerance,
            artifactPolicy: .deferred
        )
        let builderResult = try evaluator.evaluate(builderDocument)
        let commandResult = try evaluator.evaluate(commandDocument)
        let persistedResult = try evaluator.evaluate(persistedDocument)

        #expect(builderResult.brep == commandResult.brep)
        #expect(commandResult.brep == persistedResult.brep)
        #expect(builderResult.subshapes == commandResult.subshapes)
        #expect(commandResult.subshapes == persistedResult.subshapes)
        #expect(builderResult.lineage == commandResult.lineage)
        #expect(commandResult.lineage == persistedResult.lineage)
        #expect(builderResult.brep.bodies.count == 1)
        #expect(builderResult.brep.faces.count == 6)
        #expect(builderResult.brep.edges.count == 12)
        #expect(builderResult.brep.vertices.count == 8)
        #expect(builderResult.brep.geometry.surfaces.values.filter {
            if case .cylinder = $0 { return true }
            return false
        }.count == 2)
        #expect(builderResult.brep.geometry.surfaces.values.filter {
            if case .plane = $0 { return true }
            return false
        }.count == 4)
        #expect(builderResult.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        let sideFaceID = SubshapeID(
            featureID: sweepFeatureID,
            role: GeneratedSubshapeRole.sideFace.rawValue,
            ordinal: 0
        )
        guard case .face = try #require(
            builderResult.subshapes[sideFaceID]
        ) else {
            Issue.record("Expected exact revolved Sweep side face topology.")
            return
        }
        #expect(builderResult.lineage[sideFaceID]?.relation == .generated)
        try builderResult.brep.validate(
            level: .exact,
            tolerance: tolerance
        )
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
}
