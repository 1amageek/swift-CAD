import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Exact curve extend command parity")
struct CurveExtendCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalParameterizedExtension() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let distanceID = try builder.lengthParameter(named: "extension", 0.1, .meter)
        let source = try builder.sketch(on: .xy, named: "Source line") { sketch in
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
        let extensionID = try builder.extendCurve(
            CurveOutputReference(featureID: source.featureID),
            end: .both,
            distance: .reference(distanceID),
            named: "Exact extension"
        )
        let builderDocument = try builder.build(name: "Curve extend parity")

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Curve extend parity")
        )
        let editor = DocumentEditor()
        let parameters = builderDocument.parameters.parameters.values.sorted {
            $0.name < $1.name
        }
        var commands = parameters.map(CADCommand.upsertParameter)
        for featureID in builderDocument.designGraph.order {
            let node = try #require(builderDocument.designGraph.nodes[featureID])
            commands.append(CADCommand.appendFeature(FeatureRequest(
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
        let builderCurve = try #require(builderResult.curves[extensionID]?.first)
        let commandCurve = try #require(commandResult.curves[extensionID]?.first)
        let persistedCurve = try #require(persistedResult.curves[extensionID]?.first)

        #expect(builderCurve == commandCurve)
        #expect(commandCurve == persistedCurve)
        #expect(builderCurve.exactParameterDomain == .closed(-0.1, 1.1))
        guard case .line = builderCurve.exactCurve else {
            Issue.record("Curve extend command path must preserve exact line geometry.")
            return
        }
    }
}
