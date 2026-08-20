import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Exact curve offset command parity")
struct CurveOffsetCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalParameterizedOffset() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let distanceID = try builder.lengthParameter(named: "offset", 0.1, .meter)
        let source = try builder.sketch(on: .xy, named: "Source line") { sketch in
            _ = sketch.line(
                from: SketchPoint(
                    x: .constant(.length(0.0, unit: .meter)),
                    y: .constant(.length(0.0, unit: .meter))
                ),
                to: SketchPoint(
                    x: .constant(.length(1.0, unit: .meter)),
                    y: .constant(.length(0.0, unit: .meter))
                )
            )
        }
        let offsetID = try builder.offsetCurve(
            CurveOutputReference(featureID: source.featureID),
            distance: .reference(distanceID),
            planeNormal: .unitZ,
            side: .left,
            named: "Exact offset"
        )
        let builderDocument = try builder.build(name: "Curve offset parity")

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Curve offset parity")
        )
        let editor = DocumentEditor()
        var commands = builderDocument.parameters.parameters.values.sorted {
            $0.name < $1.name
        }.map(CADCommand.upsertParameter)
        for featureID in builderDocument.designGraph.order {
            let node = try #require(builderDocument.designGraph.nodes[featureID])
            commands.append(.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            )))
        }
        for command in commands {
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(CADCommand.self, from: encoded)
            #expect(decoded == command)
            commandDocument = try editor.apply(
                decoded,
                to: commandDocument,
                tolerance: .standard
            )
        }

        let persisted = try JSONEncoder().encode(commandDocument)
        let decodedDocument = try JSONDecoder().decode(CADDocument.self, from: persisted)
        #expect(try builderDocument.sourceFingerprint(tolerance: .standard)
            == commandDocument.sourceFingerprint(tolerance: .standard))
        #expect(try commandDocument.sourceFingerprint(tolerance: .standard)
            == decodedDocument.sourceFingerprint(tolerance: .standard))

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let builderResult = try evaluator.evaluate(builderDocument)
        let commandResult = try evaluator.evaluate(commandDocument)
        let persistedResult = try evaluator.evaluate(decodedDocument)
        let builderCurve = try #require(builderResult.curves[offsetID]?.first)
        let commandCurve = try #require(commandResult.curves[offsetID]?.first)
        let persistedCurve = try #require(persistedResult.curves[offsetID]?.first)

        #expect(builderCurve == commandCurve)
        #expect(commandCurve == persistedCurve)
        guard case let .line(line) = builderCurve.exactCurve else {
            Issue.record("Curve offset command path must produce an exact line.")
            return
        }
        #expect(abs(line.origin.y - 0.1) <= 1.0e-12)
    }
}
