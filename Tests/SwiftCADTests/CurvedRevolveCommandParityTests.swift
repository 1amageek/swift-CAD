import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
import SwiftCAD

@Suite("Curved revolve command parity")
struct CurvedRevolveCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalExactRevolve() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-8,
            angle: 1.0e-10
        )
        var builder = DocumentBuilder(units: .meters, tolerance: tolerance)
        let profile = try builder.sketch(on: .xy, named: "Circular profile") { sketch in
            sketch.circle(
                center: point(0.03, 0.0),
                radius: .constant(.length(0.01, unit: .meter))
            )
        }
        _ = try builder.revolve(
            profile,
            axis: RevolveAxis(origin: .origin, direction: .unitY),
            angle: .constant(.angle(180.0, unit: .degree)),
            named: "Exact half torus"
        )
        let builderDocument = try builder.build(name: "Curved revolve parity")

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Curved revolve parity")
        )
        let editor = DocumentEditor()
        for featureID in builderDocument.designGraph.order {
            let node = try #require(builderDocument.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(CADCommand.self, from: encoded)
            #expect(decoded == command)
            commandDocument = try editor.apply(
                decoded,
                to: commandDocument,
                tolerance: tolerance
            )
        }

        let persisted = try JSONEncoder().encode(commandDocument)
        let decodedDocument = try JSONDecoder().decode(
            CADDocument.self,
            from: persisted
        )
        #expect(try builderDocument.sourceFingerprint(tolerance: tolerance)
            == commandDocument.sourceFingerprint(tolerance: tolerance))
        #expect(try commandDocument.sourceFingerprint(tolerance: tolerance)
            == decodedDocument.sourceFingerprint(tolerance: tolerance))

        let evaluator = DocumentEvaluator(
            tolerance: tolerance,
            artifactPolicy: .deferred
        )
        let builderResult = try evaluator.evaluate(builderDocument)
        let commandResult = try evaluator.evaluate(commandDocument)
        let persistedResult = try evaluator.evaluate(decodedDocument)

        #expect(builderResult.brep == commandResult.brep)
        #expect(commandResult.brep == persistedResult.brep)
        #expect(builderResult.subshapes == commandResult.subshapes)
        #expect(commandResult.subshapes == persistedResult.subshapes)
        #expect(builderResult.lineage == commandResult.lineage)
        #expect(commandResult.lineage == persistedResult.lineage)
        #expect(builderResult.brep.geometry.surfaces.values.contains {
            if case .bSpline = $0 { return true }
            return false
        })
        try builderResult.brep.validate(level: .exact, tolerance: tolerance)
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
}
