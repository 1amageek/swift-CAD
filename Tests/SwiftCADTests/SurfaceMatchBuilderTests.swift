import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import SwiftCAD

@Suite("Surface match builder")
struct SurfaceMatchBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func exactRationalSurfaceMatchHasBuilderCommandAndNativePackageParity() throws {
        let sourceSurface = rationalSurface()
        let targetSurface = translated(sourceSurface, by: Vector3D(x: 2.0, y: -3.0, z: 4.0))
        let sourceParameter = SurfaceParameter(u: 0.37, v: 0.63)
        let targetParameter = SurfaceParameter(u: 0.37, v: 0.63)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sourceID = try builder.bSplineSurface(
            sourceSurface,
            named: "Rational source surface"
        )
        let targetID = try builder.bSplineSurface(
            targetSurface,
            named: "Translated rational target surface"
        )
        let matchID = try builder.matchSurface(
            source: sourceID,
            sourceParameter: sourceParameter,
            target: targetID,
            targetParameter: targetParameter,
            continuity: .curvature,
            named: "Exact rational surface match"
        )
        let builderDocument = try builder.build(name: "Surface match parity")
        let commandDocument = try replayCodableCommands(from: builderDocument)
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: commandDocument, to: sink)
        let persistedDocument = try pipeline.loadDocument(
            from: BorrowedBytes(sink.bytes)
        )

        #expect(
            try builderDocument.sourceFingerprint(tolerance: .standard)
                == commandDocument.sourceFingerprint(tolerance: .standard)
        )
        #expect(
            try commandDocument.sourceFingerprint(tolerance: .standard)
                == persistedDocument.sourceFingerprint(tolerance: .standard)
        )
        guard case .surfaceMatch = persistedDocument.designGraph.nodes[matchID]?.operation else {
            Issue.record("Native persistence must retain the exact surface match request.")
            return
        }

        let builderResult = try pipeline.evaluate(builderDocument)
        let commandResult = try pipeline.evaluate(commandDocument)
        let persistedResult = try pipeline.evaluate(persistedDocument)
        #expect(builderResult.brep == commandResult.brep)
        #expect(commandResult.brep == persistedResult.brep)
        #expect(builderResult.subshapes == commandResult.subshapes)
        #expect(commandResult.subshapes == persistedResult.subshapes)
        #expect(builderResult.lineage == commandResult.lineage)
        #expect(commandResult.lineage == persistedResult.lineage)
        try builderResult.brep.validate(level: .exact, tolerance: .standard)
        #expect(builderResult.brep.bodies.count == 1)
        #expect(builderResult.brep.faces.count == 1)
        #expect(builderResult.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        let face = try #require(builderResult.brep.faces.values.first)
        guard case let .bSpline(outputSurface) = try #require(
            builderResult.brep.geometry.surfaces[face.surfaceID]
        ) else {
            Issue.record("Surface match must retain an exact rational B-spline surface.")
            return
        }
        let continuity = try SurfaceContinuityEvaluator(
            modelingTolerance: .standard
        ).evaluate(SurfaceContinuityRequest(
            samplePairs: [SurfaceContinuitySamplePair(
                first: SurfaceContinuityTarget(
                    surface: .bSpline(outputSurface),
                    u: sourceParameter.u,
                    v: sourceParameter.v
                ),
                second: SurfaceContinuityTarget(
                    surface: .bSpline(targetSurface),
                    u: targetParameter.u,
                    v: targetParameter.v
                )
            )],
            requiredLevel: .curvature,
            tolerances: .standard(modelingTolerance: .standard)
        ))
        #expect(continuity.isSatisfied)
        #expect(builderResult.lineage.values.contains { lineage in
            lineage.output.featureID == matchID && lineage.relation == .merged
        })
    }

    private func replayCodableCommands(from source: CADDocument) throws -> CADDocument {
        let editor = DocumentEditor()
        var result = CADDocument(
            units: source.units,
            metadata: source.metadata
        )
        for featureID in source.designGraph.order {
            let node = try #require(source.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(CADCommand.self, from: encoded)
            #expect(decoded == command)
            result = try editor.apply(decoded, to: result, tolerance: .standard)
        }
        return result
    }

    private func rationalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.0, y: 0.5, z: 0.2),
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.5, y: 0.0, z: 0.1),
                    Point3D(x: 0.5, y: 0.5, z: 0.6),
                    Point3D(x: 0.5, y: 1.0, z: 0.15),
                ],
                [
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.5, z: 0.25),
                    Point3D(x: 1.0, y: 1.0, z: 0.05),
                ],
            ],
            weights: [
                [1.0, 0.85, 1.0],
                [0.9, 1.2, 0.95],
                [1.0, 0.8, 1.0],
            ]
        )
    }

    private func translated(
        _ surface: BSplineSurface3D,
        by offset: Vector3D
    ) -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uKnots: surface.uKnots,
            vKnots: surface.vKnots,
            controlPoints: surface.controlPoints.map { row in
                row.map { $0 + offset }
            },
            weights: surface.weights
        )
    }
}
