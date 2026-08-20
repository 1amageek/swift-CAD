import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Exact curve match command parity")
struct CurveMatchCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalGeneralCurveMatch() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let source = try builder.sketch(on: .xy, named: "Source line") { sketch in
            _ = sketch.line(from: point(0.0, 0.0), to: point(0.1, 0.0))
        }
        let target = try builder.sketch(on: .xy, named: "Target circle") { sketch in
            sketch.circle(center: point(0.2, 0.05), radius: length(0.05))
        }
        let matchID = try builder.matchCurve(
            CurveOutputReference(featureID: source.featureID),
            end: .end,
            to: CurveOutputReference(featureID: target.featureID),
            targetEnd: .start,
            continuity: .curvature,
            named: "General exact match"
        )
        let builderDocument = try builder.build(name: "Curve match parity")

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Curve match parity")
        )
        let editor = DocumentEditor()
        for featureID in builderDocument.designGraph.order {
            let node = try #require(builderDocument.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let decoded = try JSONDecoder().decode(
                CADCommand.self,
                from: JSONEncoder().encode(command)
            )
            #expect(decoded == command)
            commandDocument = try editor.apply(
                decoded,
                to: commandDocument,
                tolerance: .standard
            )
        }

        let persistedDocument = try JSONDecoder().decode(
            CADDocument.self,
            from: JSONEncoder().encode(commandDocument)
        )
        #expect(try builderDocument.sourceFingerprint(tolerance: .standard)
            == commandDocument.sourceFingerprint(tolerance: .standard))
        #expect(try commandDocument.sourceFingerprint(tolerance: .standard)
            == persistedDocument.sourceFingerprint(tolerance: .standard))

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let builderResult = try evaluator.evaluate(builderDocument)
        let commandResult = try evaluator.evaluate(commandDocument)
        let persistedResult = try evaluator.evaluate(persistedDocument)
        let builderCurve = try #require(builderResult.curves[matchID]?.first)
        let commandCurve = try #require(commandResult.curves[matchID]?.first)
        let persistedCurve = try #require(persistedResult.curves[matchID]?.first)
        #expect(builderCurve == commandCurve)
        #expect(commandCurve == persistedCurve)
        guard case let .bSpline(curve) = builderCurve.exactCurve else {
            Issue.record("Curve match parity must produce an exact B-spline.")
            return
        }
        let frame = try curve.differentialGeometry(at: 1.0, tolerance: .standard)
        #expect(curve.degree == 5)
        #expect(frame.position.isApproximatelyEqual(
            to: Point3D(x: 0.25, y: 0.05, z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect((frame.tangent - .unitY).length <= 1.0e-12)
        #expect(abs(frame.curvature - 20.0) <= 1.0e-6)
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: length(x), y: length(y))
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }
}
