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

    /// Trim overlap (Plasticity's Loft with guides): two guides running past both sections are
    /// cut at the sections by default, the sheet spanning only between them; with it off the
    /// sheet runs on along the guides to their ends, each end section carried there.
    @Test(.timeLimit(.minutes(2)))
    func trimOverlapCutsTheGuidesAtTheSectionsOrRunsOnToTheirEnds() throws {
        func corners(trimsOverlap: Bool) throws -> [Point3D] {
            var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
            let near = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 30), to: point(10, 30)) }.featureID
            let far = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 70), to: point(10, 70)) }.featureID
            let left = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 0), to: point(0, 100)) }.featureID
            let right = try builder.sketch(on: .xy) { _ = $0.line(from: point(10, 0), to: point(10, 100)) }.featureID
            let loft = try builder.loft(
                sections: [near, far].map { LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0))) },
                guides: [LoftGuideReference(featureID: left), LoftGuideReference(featureID: right)],
                options: LoftOptions(resultKind: .sheet, trimsOverlap: trimsOverlap)
            )
            let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
            try evaluated.brep.validate(level: .exact, tolerance: .standard)
            let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
                guard key.featureID == loft, case let .face(id) = value else { return nil }
                return id
            }
            return try faces.flatMap { faceID in
                try (evaluated.brep.faces[faceID]?.loops ?? []).flatMap { try evaluated.brep.orderedPoints(for: $0) }
            }
        }
        func spans(_ points: [Point3D], from lower: Double, to upper: Double) -> Bool {
            let ys = points.map { $0.y * 1000 }
            return abs((ys.min() ?? .nan) - lower) < 1e-6 && abs((ys.max() ?? .nan) - upper) < 1e-6
                && points.allSatisfy { $0.x * 1000 > -1e-6 && $0.x * 1000 < 10 + 1e-6 && abs($0.z) < 1e-9 }
        }
        #expect(spans(try corners(trimsOverlap: true), from: 30, to: 70))
        #expect(spans(try corners(trimsOverlap: false), from: 0, to: 100))
        // The option persists, and documents without it trim.
        let options = LoftOptions(resultKind: .sheet, trimsOverlap: false)
        #expect(try JSONDecoder().decode(LoftOptions.self, from: try JSONEncoder().encode(options)).trimsOverlap == false)
        #expect(try JSONDecoder().decode(LoftOptions.self, from: try JSONEncoder().encode(LoftOptions())).trimsOverlap)
    }

    /// Trim profiles (inferred from Trim overlap, decided 2026-10-05): two sections running past
    /// both guides are cut where the guides cross them when it is on, the sheet spanning only
    /// between the guides; off, the sections loft whole as before.
    @Test(.timeLimit(.minutes(2)))
    func trimProfilesCutsTheSectionsAtTheGuides() throws {
        func corners(trimsProfiles: Bool) throws -> [Point3D] {
            var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
            let near = try builder.sketch(on: .xy) { _ = $0.line(from: point(-5, 30), to: point(20, 30)) }.featureID
            let far = try builder.sketch(on: .xy) { _ = $0.line(from: point(-5, 70), to: point(20, 70)) }.featureID
            let left = try builder.sketch(on: .xy) { _ = $0.line(from: point(0, 30), to: point(0, 70)) }.featureID
            let right = try builder.sketch(on: .xy) { _ = $0.line(from: point(10, 30), to: point(14, 70)) }.featureID
            let loft = try builder.loft(
                sections: [near, far].map { LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0))) },
                guides: [LoftGuideReference(featureID: left), LoftGuideReference(featureID: right)],
                options: LoftOptions(resultKind: .sheet, trimsProfiles: trimsProfiles)
            )
            let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
            try evaluated.brep.validate(level: .exact, tolerance: .standard)
            let faces = evaluated.subshapes.entries.compactMap { key, value -> FaceID? in
                guard key.featureID == loft, case let .face(id) = value else { return nil }
                return id
            }
            return try faces.flatMap { faceID in
                try (evaluated.brep.faces[faceID]?.loops ?? []).flatMap { try evaluated.brep.orderedPoints(for: $0) }
            }
        }
        let trimmed = try corners(trimsProfiles: true)
        // The trapezoid between the guides: (0, 30), (10, 30), (14, 70), (0, 70).
        for expected in [(0.0, 30.0), (10.0, 30.0), (14.0, 70.0), (0.0, 70.0)] {
            #expect(trimmed.contains { abs($0.x * 1000 - expected.0) < 1e-6 && abs($0.y * 1000 - expected.1) < 1e-6 }, "\(expected)")
        }
        #expect(trimmed.allSatisfy { $0.x * 1000 > -1e-6 && $0.x * 1000 < 14 + 1e-6 })
        // The option persists, and documents without it loft whole sections.
        let options = LoftOptions(resultKind: .sheet, trimsProfiles: true)
        #expect(try JSONDecoder().decode(LoftOptions.self, from: try JSONEncoder().encode(options)).trimsProfiles)
        #expect(try JSONDecoder().decode(LoftOptions.self, from: try JSONEncoder().encode(LoftOptions())).trimsProfiles == false)
    }
}
