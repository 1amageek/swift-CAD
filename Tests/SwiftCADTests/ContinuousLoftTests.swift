import Foundation
import Testing
@testable import SwiftCAD

/// Continuous lofting: a Loft from one open section along two guides, one leaving each of its
/// ends, runs to the section carried onto the guides' far ends (Plasticity's Loft of a single
/// edge, its two neighbouring edges the guides).
@Suite("Continuous Loft")
struct ContinuousLoftTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: millimeters(x), y: millimeters(y)) }

    @Test(.timeLimit(.minutes(1)))
    func oneSectionLoftsAlongTwoGuidesToTheirFarEnds() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let section = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 0), to: point(10, 0)) }.featureID
        let left = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 0), to: point(0, 10)) }.featureID
        let right = try builder.sketch(on: .xy) { _ = $0.line(from: point(10, 0), to: point(12, 10)) }.featureID
        let loft = try builder.loft(
            sections: [LoftSectionReference(section: .curve(CurveSectionReference(featureID: section)))],
            guides: [LoftGuideReference(featureID: left), LoftGuideReference(featureID: right)],
            options: LoftOptions(resultKind: .sheet)
        )
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
            guard key.featureID == loft, case let .face(id) = value else { return nil }
            return id
        }
        #expect(faces.count == 1)
        // The far section is the 10 mm line carried onto the guides' far ends: from (0, 10) to
        // (12, 10), so the sheet is the trapezoid between them.
        let corners = try faces.flatMap { faceID in
            try (evaluated.brep.faces[faceID]?.loops ?? []).flatMap { try evaluated.brep.orderedPoints(for: $0) }
        }
        for expected in [(0.0, 0.0), (10.0, 0.0), (12.0, 10.0), (0.0, 10.0)] {
            #expect(corners.contains { abs($0.x - expected.0 * 0.001) < 1e-9 && abs($0.y - expected.1 * 0.001) < 1e-9 && abs($0.z) < 1e-9 },
                    "\(expected)")
        }
        let surface = try #require(faces.first.flatMap { evaluated.brep.faces[$0] }.flatMap { evaluated.brep.geometry.surfaces[$0.surfaceID] })
        let middle = Point3D(x: 0.006, y: 0.010, z: 0)
        let foot = try surface.parameterProjection(of: middle, tolerance: .standard)
        let onSurface = try surface.differentialGeometry(u: foot.u, v: foot.v, tolerance: .standard).position
        #expect((onSurface - middle).length < 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func oneSectionWithoutAGuideAtEachEndIsRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let section = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 0), to: point(10, 0)) }.featureID
        let left = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 0), to: point(0, 10)) }.featureID
        let stray = try builder.sketch(on: .xy) { _ = $0.line(from: point(20, 0), to: point(20, 10)) }.featureID
        _ = try builder.loft(
            sections: [LoftSectionReference(section: .curve(CurveSectionReference(featureID: section)))],
            guides: [LoftGuideReference(featureID: left), LoftGuideReference(featureID: stray)],
            options: LoftOptions(resultKind: .sheet)
        )
        #expect(throws: (any Error).self) { _ = try CADPipeline(tolerance: .standard).evaluate(builder.build()) }
    }
}
