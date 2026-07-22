import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import SwiftCAD

@Suite("Exact B-spline surface command parity")
struct BSplineSurfaceCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndPersistenceProduceIdenticalValidatedSheet() throws {
        let surface = rationalSurface()
        let parameterDomain = SurfaceParameterDomain2D(
            uLowerBound: 0.2,
            uUpperBound: 0.8,
            vLowerBound: 0.1,
            vUpperBound: 0.9
        )
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let featureID = try builder.bSplineSurface(
            surface,
            parameterDomain: parameterDomain,
            named: "Exact rational patch"
        )
        let builderDocument = try builder.build(name: "B-spline parity")
        let node = try #require(builderDocument.designGraph.nodes[featureID])
        let command = CADCommand.appendFeature(FeatureRequest(
            id: node.id,
            name: node.name,
            operation: node.operation
        ))
        let commandData = try JSONEncoder().encode(command)
        let decodedCommand = try JSONDecoder().decode(CADCommand.self, from: commandData)
        let commandDocument = try DocumentEditor().apply(
            decodedCommand,
            to: CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: "B-spline parity")
            ),
            tolerance: .standard
        )
        let persistedData = try JSONEncoder().encode(commandDocument)
        let persistedDocument = try JSONDecoder().decode(
            CADDocument.self,
            from: persistedData
        )

        #expect(try builderDocument.sourceFingerprint(tolerance: .standard)
            == commandDocument.sourceFingerprint(tolerance: .standard))
        #expect(try commandDocument.sourceFingerprint(tolerance: .standard)
            == persistedDocument.sourceFingerprint(tolerance: .standard))

        let evaluator = DocumentEvaluator(
            tolerance: .standard,
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

        try builderResult.brep.validate(level: .exact, tolerance: .standard)
        let face = try #require(builderResult.brep.faces.values.first)
        guard case let .bSpline(evaluatedSurface) = try #require(
            builderResult.brep.geometry.surfaces[face.surfaceID]
        ) else {
            Issue.record("B-spline surface command paths must retain exact surface geometry.")
            return
        }
        #expect(evaluatedSurface == surface)
        let loopID = try #require(face.loops.first)
        let loop = try #require(builderResult.brep.loops[loopID])
        #expect(loop.coedges.count == 4)
        #expect(loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil })
    }

    private func rationalSurface() -> BSplineSurface3D {
        let base = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: .origin,
            bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.0),
            topRight: Point3D(x: 2.0, y: 1.0, z: 0.25),
            topLeft: Point3D(x: 0.0, y: 1.0, z: 0.0)
        )
        var weights = base.weights
        weights[1][1] = 1.5
        return BSplineSurface3D(
            uDegree: base.uDegree,
            vDegree: base.vDegree,
            uKnots: base.uKnots,
            vKnots: base.vKnots,
            controlPoints: base.controlPoints,
            weights: weights
        )
    }
}
