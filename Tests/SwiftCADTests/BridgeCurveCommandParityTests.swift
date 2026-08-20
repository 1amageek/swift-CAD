import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Exact bridge curve command parity")
struct BridgeCurveCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandPersistenceAndUpstreamReplacementStayIdentical() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let startSource = try builder.sketch(on: .xy, named: "Start source") { sketch in
            _ = sketch.line(
                from: point(-1.0, 0.0),
                to: point(0.0, 0.0)
            )
        }
        let endSource = try builder.sketch(on: .xy, named: "End source") { sketch in
            _ = sketch.line(
                from: point(2.0, 1.0),
                to: point(2.0, 2.0)
            )
        }
        let bridgeID = try builder.bridgeCurve(
            from: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: startSource.featureID),
                end: .end,
                requiredLevel: .curvature
            ),
            to: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: endSource.featureID),
                end: .start,
                requiredLevel: .curvature
            ),
            continuityTolerances: .standard(modelingTolerance: .standard),
            named: "Exact bridge"
        )
        let builderDocument = try builder.build(name: "Bridge parity")

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Bridge parity")
        )
        let editor = DocumentEditor()
        for featureID in builderDocument.designGraph.order {
            let node = try #require(builderDocument.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let encodedCommand = try JSONEncoder().encode(command)
            let decodedCommand = try JSONDecoder().decode(CADCommand.self, from: encodedCommand)
            #expect(decodedCommand == command)
            commandDocument = try editor.apply(
                decodedCommand,
                to: commandDocument,
                tolerance: .standard
            )
        }

        let persisted = try JSONEncoder().encode(commandDocument)
        let persistedDocument = try JSONDecoder().decode(CADDocument.self, from: persisted)
        #expect(try builderDocument.sourceFingerprint(tolerance: .standard)
            == commandDocument.sourceFingerprint(tolerance: .standard))
        #expect(try commandDocument.sourceFingerprint(tolerance: .standard)
            == persistedDocument.sourceFingerprint(tolerance: .standard))

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let builderResult = try evaluator.evaluate(builderDocument)
        let commandResult = try evaluator.evaluate(commandDocument)
        let persistedResult = try evaluator.evaluate(persistedDocument)
        let builderCurve = try #require(builderResult.curves[bridgeID]?.first)
        let commandCurve = try #require(commandResult.curves[bridgeID]?.first)
        let persistedCurve = try #require(persistedResult.curves[bridgeID]?.first)
        #expect(builderCurve == commandCurve)
        #expect(commandCurve == persistedCurve)
        guard case let .bSpline(exactBridge) = builderCurve.exactCurve else {
            Issue.record("Shared command paths must preserve exact bridge geometry.")
            return
        }
        #expect(exactBridge.degree == 5)

        let replacement = CADCommand.replaceFeature(FeatureRequest(
            id: endSource.featureID,
            name: "End source",
            operation: .sketch(lineSketch(
                from: Point2D(x: 3.0, y: 1.0),
                to: Point2D(x: 3.0, y: 2.0)
            ))
        ))
        let replacedDocument = try editor.apply(
            replacement,
            to: commandDocument,
            tolerance: .standard
        )
        let replacedResult = try evaluator.evaluate(replacedDocument)
        let replacedBridge = try #require(replacedResult.curves[bridgeID]?.first?.exactCurve)
        let replacedEnd = try replacedBridge.point(at: 1.0, tolerance: .standard)
        #expect(replacedEnd == Point3D(x: 3.0, y: 1.0, z: 0.0))
        let bridgeNode = try #require(replacedDocument.designGraph.nodes[bridgeID])
        #expect(bridgeNode.inputs == [
            FeatureInput(featureID: startSource.featureID, role: .curve),
            FeatureInput(featureID: endSource.featureID, role: .target),
        ])
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }

    private func lineSketch(from start: Point2D, to end: Point2D) -> Sketch {
        Sketch(
            plane: .xy,
            entities: [
                SketchEntityID(): .line(SketchLine(
                    start: point(start.x, start.y),
                    end: point(end.x, end.y)
                )),
            ]
        )
    }
}
