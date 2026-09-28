import Foundation
import Testing
@testable import SwiftCAD

/// Mirror of sheets: a sheet mirrors to a sheet, is kept beside its reflection when clear of the
/// plane, is sewn to it along the edge where it meets the plane, and is refused where it may cross.
@Suite("Sheet mirror integration")
struct SheetMirrorIntegrationTests {
    /// A quadratic patch over x ∈ [x0, x1], y ∈ [0, 0.02] whose middle column of control points
    /// sits at `middleX`, so the patch bulges in x and rises to z = 0.01 in its middle row.
    private func patch(x0: Double, x1: Double, middleX: Double? = nil) -> BSplineSurface3D {
        let xs = [x0, middleX ?? (x0 + x1) / 2, x1]
        let ys = [0.0, 0.01, 0.02]
        return BSplineSurface3D(
            uDegree: 2, vDegree: 2,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: ys.map { y in
                xs.enumerated().map { index, x in Point3D(x: x, y: y, z: index == 1 ? 0.01 : 0) }
            }
        )
    }

    private func evaluate(_ surface: BSplineSurface3D, output: MirrorFeature.Output = .combined, cuts: Bool = false) throws -> (EvaluatedDocument, FeatureID, CADDocument) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheetID = try builder.bSplineSurface(surface)
        let mirrorID = try builder.mirror(
            sheetID, planeOrigin: .origin, planeNormal: .unitX, output: output, cutsAtPlane: cuts
        )
        let document = try builder.build(name: "Sheet mirror")
        return (try CADPipeline(tolerance: .standard).evaluate(document), mirrorID, document)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSheetClearOfThePlaneIsKeptBesideItsReflection() throws {
        let (evaluated, mirrorID, document) = try evaluate(patch(x0: 0.01, x1: 0.03))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(document.designGraph.nodes[mirrorID]?.outputs.map(\.role) == [.sheet])
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.shells.count == 2)
        #expect(evaluated.brep.faces.count == 2)
        let xs = evaluated.brep.vertices.values.map(\.point.x)
        #expect(abs((xs.min() ?? .nan) + 0.03) <= 1.0e-9)
        #expect(abs((xs.max() ?? .nan) - 0.03) <= 1.0e-9)
        let lineage = evaluated.lineage.values.filter { $0.output.featureID == mirrorID }
        #expect(lineage.isEmpty == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSheetMeetingThePlaneAlongAnEdgeIsSewnToItsReflection() throws {
        let (evaluated, _, _) = try evaluate(patch(x0: 0, x1: 0.02))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 2)
        // Two patches of four edges share the one on the plane.
        #expect(evaluated.brep.edges.count == 7)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSheetThatMayCrossThePlaneIsRefused() throws {
        // Both ends lie on the positive side, but the bulge reaches past the plane.
        #expect(throws: (any Error).self) {
            _ = try evaluate(patch(x0: 0.005, x1: 0.02, middleX: -0.02))
        }
        #expect(throws: (any Error).self) {
            _ = try evaluate(patch(x0: -0.01, x1: 0.02))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aSheetMirrorsAloneAndCanBeCut() throws {
        let (reflected, mirrorID, document) = try evaluate(patch(x0: -0.01, x1: 0.02), output: .reflection)
        try reflected.brep.validate(level: .exact, tolerance: .standard)
        #expect(document.designGraph.nodes[mirrorID]?.outputs.map(\.role) == [.sheet])
        #expect(reflected.brep.faces.count == 1)
        let xs = reflected.brep.vertices.values.map(\.point.x)
        #expect(abs((xs.min() ?? .nan) + 0.02) <= 1.0e-9)
        #expect(abs((xs.max() ?? .nan) - 0.01) <= 1.0e-9)

        let (cut, _, _) = try evaluate(patch(x0: -0.01, x1: 0.02), output: .kept, cuts: true)
        try cut.brep.validate(level: .exact, tolerance: .standard)
        #expect(cut.brep.vertices.values.allSatisfy { $0.point.x <= 1e-8 })

    }
}
