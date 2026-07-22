import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Exact curve trim command parity")
struct CurveTrimCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalExactTrim() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let source = try builder.sketch(on: .xy, named: "Source curve") { sketch in
            sketch.line(
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
        let trimID = try builder.trimCurve(
            CurveOutputReference(featureID: source.featureID),
            domain: .closed(0.2, 0.8),
            named: "Exact trim"
        )
        let builderDocument = try builder.build(name: "Curve trim parity")

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Curve trim parity")
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
        let builderCurve = try #require(builderResult.curves[trimID]?.first)
        let commandCurve = try #require(commandResult.curves[trimID]?.first)
        let persistedCurve = try #require(persistedResult.curves[trimID]?.first)

        #expect(builderCurve == commandCurve)
        #expect(commandCurve == persistedCurve)
        #expect(builderCurve.exactParameterDomain == .closed(0.2, 0.8))
        guard case .line = builderCurve.exactCurve else {
            Issue.record("Curve trim command path must preserve exact line geometry.")
            return
        }
    }
}
