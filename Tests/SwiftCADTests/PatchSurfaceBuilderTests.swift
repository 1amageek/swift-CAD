import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import SwiftCAD

@Suite("Patch surface Builder")
struct PatchSurfaceBuilderTests {
    private struct Boundaries {
        var vMinimum: BSplineCurve3D
        var vMaximumReversed: BSplineCurve3D
        var uMinimum: BSplineCurve3D
        var uMaximumReversed: BSplineCurve3D
    }

    private static let testTolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceExactPolynomialCoonsSheet() throws {
        let boundaries = supportedBoundaries()
        var builder = DocumentBuilder(units: .meters, tolerance: Self.testTolerance)
        let featureID = try builder.patchSurface(
            vMinimumBoundary: boundaries.vMinimum,
            vMaximumBoundary: boundaries.vMaximumReversed,
            uMinimumBoundary: boundaries.uMinimum,
            uMaximumBoundary: boundaries.uMaximumReversed,
            vMaximumOrientation: .reversed,
            uMaximumOrientation: .reversed,
            named: "Polynomial Coons patch"
        )
        let builderDocument = try builder.build(name: "Patch surface")
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
            Issue.record("Patch surface must retain exact polynomial B-spline geometry.")
            return
        }
        #expect(surface.uDegree == 3)
        #expect(surface.vDegree == 2)
        #expect(surface.isRational == false)
        #expect(surface.uControlPointCount == 4)
        #expect(surface.vControlPointCount == 3)

        let orientedVMaximum = try boundaries.vMaximumReversed.reversed(
            tolerance: Self.testTolerance
        )
        let orientedUMaximum = try boundaries.uMaximumReversed.reversed(
            tolerance: Self.testTolerance
        )
        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let residuals = [
                try (surface.point(u: fraction, v: 0.0, tolerance: Self.testTolerance)
                    - boundaries.vMinimum.point(
                        at: 2.0 + 3.0 * fraction,
                        tolerance: Self.testTolerance
                    )).length,
                try (surface.point(u: fraction, v: 1.0, tolerance: Self.testTolerance)
                    - orientedVMaximum.point(
                        at: -1.0 + 2.0 * fraction,
                        tolerance: Self.testTolerance
                    )).length,
                try (surface.point(u: 0.0, v: fraction, tolerance: Self.testTolerance)
                    - boundaries.uMinimum.point(
                        at: 10.0 + 2.0 * fraction,
                        tolerance: Self.testTolerance
                    )).length,
                try (surface.point(u: 1.0, v: fraction, tolerance: Self.testTolerance)
                    - orientedUMaximum.point(
                        at: 4.0 + 4.0 * fraction,
                        tolerance: Self.testTolerance
                    )).length,
            ]
            #expect((residuals.max() ?? 0.0) <= Self.testTolerance.distance)
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

    @Test(.timeLimit(.minutes(1)))
    func nonUniformRationalBoundaryReturnsTypedUnsupportedCapability() throws {
        var boundaries = supportedBoundaries()
        boundaries.vMinimum.weights = [1.0, 0.7, 1.0, 1.0]
        var builder = DocumentBuilder(units: .meters, tolerance: Self.testTolerance)
        do {
            _ = try builder.patchSurface(
                vMinimumBoundary: boundaries.vMinimum,
                vMaximumBoundary: boundaries.vMaximumReversed,
                uMinimumBoundary: boundaries.uMinimum,
                uMaximumBoundary: boundaries.uMaximumReversed,
                vMaximumOrientation: .reversed,
                uMaximumOrientation: .reversed
            )
            Issue.record("Unsupported rational patch boundaries must not be approximated.")
        } catch let error as KernelError {
            #expect(error.phase == .validation)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == Self.testTolerance)
        }
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
            result = try editor.apply(
                decoded,
                to: result,
                tolerance: Self.testTolerance
            )
        }
        return result
    }

    private func supportedBoundaries() -> Boundaries {
        Boundaries(
            vMinimum: BSplineCurve3D(
                degree: 3,
                knots: [2.0, 2.0, 2.0, 2.0, 5.0, 5.0, 5.0, 5.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.4),
                    Point3D(x: 2.0, y: 0.0, z: -0.2),
                    Point3D(x: 3.0, y: 0.0, z: 0.0),
                ]
            ),
            vMaximumReversed: BSplineCurve3D(
                degree: 3,
                knots: [-1.0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 3.0, y: 3.0, z: 0.0),
                    Point3D(x: 2.0, y: 3.0, z: 0.3),
                    Point3D(x: 1.0, y: 3.0, z: 0.7),
                    Point3D(x: 0.0, y: 3.0, z: 0.0),
                ]
            ),
            uMinimum: BSplineCurve3D(
                degree: 2,
                knots: [10.0, 10.0, 10.0, 12.0, 12.0, 12.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.0, y: 1.5, z: -0.2),
                    Point3D(x: 0.0, y: 3.0, z: 0.0),
                ]
            ),
            uMaximumReversed: BSplineCurve3D(
                degree: 2,
                knots: [4.0, 4.0, 4.0, 8.0, 8.0, 8.0],
                controlPoints: [
                    Point3D(x: 3.0, y: 3.0, z: 0.0),
                    Point3D(x: 3.0, y: 1.5, z: 0.3),
                    Point3D(x: 3.0, y: 0.0, z: 0.0),
                ]
            )
        )
    }
}
