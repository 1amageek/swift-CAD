import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import SwiftCAD

@Suite("Bridge surface Builder")
struct BridgeSurfaceBuilderTests {
    private static let testTolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func incompatibleBoundaryBasesReturnTypedValidationError() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: Self.testTolerance)
        do {
            _ = try builder.bridgeSurface(
                startBoundary: startBoundary(),
                endBoundary: BSplineCurve3D(
                    degree: 1,
                    knots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [
                        Point3D(x: 0.0, y: 3.0, z: 0.0),
                        Point3D(x: 2.0, y: 3.0, z: 0.0),
                    ]
                )
            )
            Issue.record("Incompatible bridge boundary bases must not be approximated.")
        } catch let error as KernelError {
            #expect(error.phase == .validation)
            #expect(error.code == .invalidInput)
            #expect(error.tolerance == Self.testTolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceExactRationalRuledSheet() throws {
        let start = startBoundary()
        let end = endBoundary()
        var builder = DocumentBuilder(units: .meters, tolerance: Self.testTolerance)
        let featureID = try builder.bridgeSurface(
            startBoundary: start,
            endBoundary: end,
            endOrientation: .reversed,
            named: "Rational ruled bridge"
        )
        let builderDocument = try builder.build(name: "Bridge surface")
        let replayedDocument = try replayCodableCommands(from: builderDocument)
        #expect(
            try replayedDocument.sourceFingerprint(tolerance: Self.testTolerance)
                == builderDocument.sourceFingerprint(tolerance: Self.testTolerance)
        )

        let evaluated = try DocumentEvaluator(
            tolerance: Self.testTolerance,
            artifactPolicy: .deferred
        ).evaluate(replayedDocument)
        try evaluated.brep.validate(level: .exact, tolerance: Self.testTolerance)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })

        let face = try #require(evaluated.brep.faces.values.first)
        guard case let .bSpline(surface) = try #require(
            evaluated.brep.geometry.surfaces[face.surfaceID]
        ) else {
            Issue.record("Bridge surface must retain exact rational B-spline geometry.")
            return
        }
        #expect(surface.uDegree == 2)
        #expect(surface.vDegree == 1)
        #expect(surface.isRational)
        let orientedEnd = try end.reversed(tolerance: Self.testTolerance)
        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let startParameter = fraction
            let endParameter = 2.0 + 3.0 * fraction
            let startResidual = try (
                surface.point(u: startParameter, v: 0.0, tolerance: Self.testTolerance)
                    - start.point(at: startParameter, tolerance: Self.testTolerance)
            ).length
            let endResidual = try (
                surface.point(u: startParameter, v: 1.0, tolerance: Self.testTolerance)
                    - orientedEnd.point(at: endParameter, tolerance: Self.testTolerance)
            ).length
            #expect(startResidual <= Self.testTolerance.distance)
            #expect(endResidual <= Self.testTolerance.distance)
        }

        let lineage = evaluated.lineage.values.filter {
            $0.output.featureID == featureID
        }
        #expect(lineage.isEmpty == false)
        #expect(lineage.allSatisfy { $0.parents.isEmpty })
        #expect(evaluated.subshapes.entries.keys.contains { key in
            key.featureID == featureID && key.role == GeneratedSubshapeRole.body.rawValue
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
            result = try editor.apply(decoded, to: result, tolerance: Self.testTolerance)
        }
        return result
    }

    private func startBoundary() -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.6, 1.0]
        )
    }

    private func endBoundary() -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 2,
            knots: [2.0, 2.0, 2.0, 5.0, 5.0, 5.0],
            controlPoints: [
                Point3D(x: 2.0, y: 3.0, z: 0.0),
                Point3D(x: 1.0, y: 3.0, z: 1.0),
                Point3D(x: 0.0, y: 3.0, z: 0.0),
            ],
            weights: [1.0, 0.6, 1.0]
        )
    }
}
