import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Exact curve edit command parity")
struct CurveEditCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalExactCurveEdit() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let source = try builder.sketch(on: .xy, named: "Source spline") { sketch in
            sketch.spline(SketchSpline(controlPoints: [
                point(0.0, 0.0),
                point(0.25, 0.5),
                point(0.75, 0.5),
                point(1.0, 0.0),
            ]))
        }
        let sourceReference = CurveOutputReference(featureID: source.featureID)
        let editID = try builder.editCurve(
            sourceReference,
            edits: [
                .setControlPoint(CurveControlPointEdit(
                    target: CurveControlPointReference(
                        curve: sourceReference,
                        controlPointIndex: 1
                    ),
                    point: Point3D(x: 0.25, y: 0.75, z: 0.0)
                )),
                .setWeight(CurveWeightEdit(
                    target: CurveControlPointReference(
                        curve: sourceReference,
                        controlPointIndex: 2
                    ),
                    value: 0.5
                )),
            ],
            named: "Exact edit"
        )
        let builderDocument = try builder.build(name: "Curve edit parity")

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Curve edit parity")
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
        let builderCurve = try #require(builderResult.curves[editID]?.first)
        let commandCurve = try #require(commandResult.curves[editID]?.first)
        let persistedCurve = try #require(persistedResult.curves[editID]?.first)

        #expect(builderCurve == commandCurve)
        #expect(commandCurve == persistedCurve)
        guard case let .bSpline(curve) = builderCurve.exactCurve else {
            Issue.record("Curve edit command path must produce an exact B-spline curve.")
            return
        }
        #expect(curve.controlPoints[1] == Point3D(x: 0.25, y: 0.75, z: 0.0))
        #expect(curve.weights[2] == 0.5)
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
}
