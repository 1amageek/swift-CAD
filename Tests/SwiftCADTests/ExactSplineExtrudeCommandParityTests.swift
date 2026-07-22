import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADTopology
import SwiftCAD

@Suite("Exact spline extrude command parity")
struct ExactSplineExtrudeCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalExactExtrude() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-8,
            angle: 1.0e-10
        )
        var builder = DocumentBuilder(
            units: .meters,
            tolerance: tolerance
        )
        let profile = try builder.sketch(on: .xy, named: "Spline profile") { sketch in
            sketch.spline(SketchSpline(
                controlPoints: closedSplineControlPoints(),
                isClosed: true
            ))
        }
        _ = try builder.extrude(
            profile,
            distance: .constant(.length(0.03, unit: .meter)),
            direction: .vector(Vector3D(x: 0.2, y: 0.1, z: 1.0)),
            named: "Exact oblique spline extrude"
        )
        let builderDocument = try builder.build(
            name: "Exact spline extrude parity"
        )

        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Exact spline extrude parity")
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
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(
                CADCommand.self,
                from: encoded
            )
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
        #expect(builderResult.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 4)
        #expect(builderResult.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try builderResult.brep.validate(
            level: .exact,
            tolerance: tolerance
        )
        try builderResult.brep.validate(
            level: .volumetric,
            tolerance: tolerance
        )
        let builderVolume = try builderResult.brep.volume(tolerance: tolerance)
        let commandVolume = try commandResult.brep.volume(tolerance: tolerance)
        let persistedVolume = try persistedResult.brep.volume(tolerance: tolerance)
        #expect(builderVolume > tolerance.distance * tolerance.distance * tolerance.distance)
        #expect(builderVolume == commandVolume)
        #expect(builderVolume == persistedVolume)
    }

    private func closedSplineControlPoints() -> [SketchPoint] {
        let radius = 0.01
        let kappa = 0.552_284_749_830_793_6
        return [
            point(radius, 0.0),
            point(radius, kappa * radius),
            point(kappa * radius, radius),
            point(0.0, radius),
            point(-kappa * radius, radius),
            point(-radius, kappa * radius),
            point(-radius, 0.0),
            point(-radius, -kappa * radius),
            point(-kappa * radius, -radius),
            point(0.0, -radius),
            point(kappa * radius, -radius),
            point(radius, -kappa * radius),
            point(radius, 0.0),
        ]
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
}
