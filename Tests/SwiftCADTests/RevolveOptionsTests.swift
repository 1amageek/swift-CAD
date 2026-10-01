import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A revolve combines with the bodies it targets, walls its section in by a thickness, makes a
/// solid of a curve that closes along its axis, and revolves a planar face of a body.
@Suite("Revolve options")
struct RevolveOptionsTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func degrees(_ value: Double) -> CADExpression { .constant(.angle(value, unit: .degree)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "revolve"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    /// A 10 × 300 mm strip 20–30 mm from the axis x = 50 mm.
    private func strip(in builder: inout DocumentBuilder) throws -> ProfileReference {
        try builder.sketch(on: .xy) { sketch in
            let corners = [point(0.02, -0.1), point(0.03, -0.1), point(0.03, 0.2), point(0.02, 0.2)]
            for index in corners.indices { _ = sketch.line(from: corners[index], to: corners[(index + 1) % corners.count]) }
        }
    }

    private let axis = RevolveAxis(origin: Point3D(x: 0.05, y: 0, z: 0), direction: .unitY)

    /// A 10 × 60 mm strip 20–30 mm from the axis x = 50 mm: a tube inside the box's depth, which
    /// the box's x = 60 mm face cuts along the tube's length.
    private func shortStrip(in builder: inout DocumentBuilder) throws -> ProfileReference {
        try builder.sketch(on: .xy) { sketch in
            let corners = [point(0.02, 0.02), point(0.03, 0.02), point(0.03, 0.08), point(0.02, 0.08)]
            for index in corners.indices { _ = sketch.line(from: corners[index], to: corners[(index + 1) % corners.count]) }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aRevolvedTubeCutsItsTargetOrKeepsWhatItShares() throws {
        // The box's x = 60 mm face runs along the tube, meeting its walls between their quarter-turn
        // seams.
        func segment(_ r: Double) -> Double { r * r * acos(0.01 / r) - 0.01 * (r * r - 0.0001).squareRoot() }
        // The annulus beyond 10 mm from the axis, along the 60 mm tube.
        let shared = (segment(0.03) - segment(0.02)) * 0.06
        func box(in builder: inout DocumentBuilder) throws -> FeatureID {
            try builder.box(
                placement: PrimitivePlacement(origin: Point3D(x: 0.06, y: 0, z: -0.05), axis: .unitZ, referenceDirection: .unitX),
                width: length(0.1), depth: length(0.1), height: length(0.1)
            )
        }
        for (operation, expected) in [(SolidOperation.difference, 0.001 - shared), (.intersect, shared)] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let target = try box(in: &builder)
            let profile = try shortStrip(in: &builder)
            _ = try builder.revolve(profile, axis: axis, operation: operation, targets: [target])
            let evaluated = try evaluate(builder)
            #expect(evaluated.brep.bodies.count == 1)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1e-12)
        }

        // A tube through the box, across its faces at y = 0 and y = 100 mm.
        var through = DocumentBuilder(units: .meters, tolerance: .standard)
        let crossed = try through.box(
            placement: PrimitivePlacement(origin: Point3D(x: 0, y: 0, z: -0.05), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.1), depth: length(0.1), height: length(0.1)
        )
        _ = try through.revolve(try strip(in: &through), axis: axis, operation: .difference, targets: [crossed])
        let bored = try evaluate(through)
        #expect(abs(try bored.brep.volume(tolerance: .standard) - (0.001 - Double.pi * (0.03 * 0.03 - 0.02 * 0.02) * 0.1)) < 1e-12)

        var kept = DocumentBuilder(units: .meters, tolerance: .standard)
        let target = try box(in: &kept)
        let profile = try shortStrip(in: &kept)
        _ = try kept.revolve(profile, axis: axis, operation: .difference, targets: [target], keepTools: true)
        let evaluated = try evaluate(kept)
        // Keep Tools keeps the operands beside the cut box, as a Boolean feature does; which of
        // them the document shows is the application's choice.
        let tube = Double.pi * (0.03 * 0.03 - 0.02 * 0.02) * 0.06
        #expect(evaluated.brep.bodies.count == 3)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (0.001 - shared + tube + 0.001)) < 1e-12)

        let document = try kept.build(name: "revolve")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func aThinRevolveWallsItsSectionIn() throws {
        for turn in [360.0, 90.0] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let profile = try strip(in: &builder)
            _ = try builder.revolve(profile, axis: axis, angle: degrees(turn), thickness: length(0.002))
            let evaluated = try evaluate(builder)
            // Pappus: the 2 mm ring of the strip, 6 × 296 mm hollow, centred 25 mm from the axis.
            let ring = 0.01 * 0.3 - 0.006 * 0.296
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - turn / 360 * 2 * Double.pi * 0.025 * ring) < 1e-12)
        }

        // A section with a hole walls each loop into a ring: both revolve into one body, a solid each.
        for turn in [360.0, 90.0] {
            var holed = DocumentBuilder(units: .meters, tolerance: .standard)
            let profile = try holed.sketch(on: .xy) { sketch in
                let corners = [point(0.02, -0.1), point(0.03, -0.1), point(0.03, 0.2), point(0.02, 0.2)]
                for index in corners.indices { _ = sketch.line(from: corners[index], to: corners[(index + 1) % corners.count]) }
                sketch.circle(center: point(0.025, 0), radius: length(0.002))
            }
            _ = try holed.revolve(profile, axis: axis, angle: degrees(turn), thickness: length(0.001))
            let evaluated = try evaluate(holed)
            // The strip's 1 mm ring (10 × 300 mm less 8 × 298 mm) and the hole's (radius 3 mm less
            // 2 mm), both centred 25 mm from the axis.
            let rings = 0.01 * 0.3 - 0.008 * 0.298 + Double.pi * (0.003 * 0.003 - 0.002 * 0.002)
            #expect(evaluated.brep.bodies.count == 1)
            #expect(abs(try evaluated.brep.volume(tolerance: .standard) - turn / 360 * 2 * Double.pi * 0.025 * rings) < 1e-12)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aCurveClosingAlongTheAxisRevolvesIntoASolid() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let arc = try builder.sketch(on: .xy) { sketch in
            sketch.arc(center: point(0, 0), radius: length(0.01), startAngle: degrees(-90), endAngle: degrees(90))
        }
        let yAxis = RevolveAxis(origin: .origin, direction: .unitY)
        var sphere = builder
        _ = try sphere.revolve(section: .curve(CurveSectionReference(featureID: arc.featureID)), axis: yAxis, resultKind: .solid)
        let evaluated = try evaluate(sphere)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 4.0 / 3.0 * Double.pi * 1e-6) < 1e-12)

        // Ends off the axis leave the revolved surface open: a sheet, not a solid.
        _ = try builder.revolve(
            section: .curve(CurveSectionReference(featureID: arc.featureID)),
            axis: RevolveAxis(origin: Point3D(x: -0.005, y: 0, z: 0), direction: .unitY), resultKind: .solid
        )
        #expect(throws: (any Error).self) { _ = try evaluate(builder) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsSideRevolvesIntoATubeBesideIt() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            let outward = face.orientation == .forward ? plane.normal : plane.normal * -1
            return outward.x < -0.99
        }?.key)
        let side = try builder.stableSubshape(key)
        // The x = 0 side, 10–30 mm from an axis along Y through z = −10 mm.
        _ = try builder.revolve(
            section: .face(FaceSectionReference(featureID: box, face: side, bodyRole: .body)),
            axis: RevolveAxis(origin: Point3D(x: 0, y: 0, z: -0.01), direction: .unitY), resultKind: .solid
        )
        let revolved = try evaluate(builder)
        #expect(revolved.brep.bodies.count == 2)
        let tube = Double.pi * (0.03 * 0.03 - 0.01 * 0.01) * 0.02
        #expect(abs(try revolved.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 + tube)) < 1e-12)
    }
}
