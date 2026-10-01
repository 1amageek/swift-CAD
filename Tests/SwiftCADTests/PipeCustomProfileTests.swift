import Foundation
import Testing
import CADCore
import CADExchange
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A pipe's custom profile is carried so its area centroid sits on the path's start and its plane
/// stands across the path, turned by the pipe's angle and hollowed to its wall.
@Suite("Pipe custom profile")
struct PipeCustomProfileTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "pipe"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    /// A 50 mm line up the Z axis from (10 mm, 0, 0) (sketch x is world z on the ZX plane).
    private func path(in builder: inout DocumentBuilder) throws -> FeatureID {
        try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0), y: length(0.01)), to: SketchPoint(x: length(0.05), y: length(0.01)))
        }.featureID
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    private func hasVertex(_ evaluated: EvaluatedDocument, _ expected: Point3D) -> Bool {
        evaluated.brep.vertices.values.contains { ($0.point - expected).length < 1e-9 }
    }

    @Test(.timeLimit(.minutes(2)))
    func aRegionIsCentredOnThePathAndTurnedByTheAngle() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A right triangle whose centroid is (2 mm, 2 mm, 0).
        let triangle = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(0, 0), to: point(0.006, 0))
            _ = sketch.line(from: point(0.006, 0), to: point(0, 0.006))
            _ = sketch.line(from: point(0, 0.006), to: point(0, 0))
        }.featureID
        let line = try path(in: &builder)
        var turned = builder
        _ = try builder.pipe(along: line, profile: .profile(ProfileReference(featureID: triangle)), approximationTolerance: length(1e-7))
        let placed = try evaluate(builder)
        #expect(abs(try placed.brep.volume(tolerance: .standard) - 0.5 * 0.006 * 0.006 * 0.05) < 1e-12)
        // The triangle slides so its centroid is the path's start.
        for corner in [Point3D(x: 0.008, y: -0.002, z: 0), Point3D(x: 0.014, y: -0.002, z: 0), Point3D(x: 0.008, y: 0.004, z: 0)] {
            #expect(hasVertex(placed, corner))
        }
        _ = try turned.pipe(along: line, profile: .profile(ProfileReference(featureID: triangle)),
                            angle: .constant(.angle(90, unit: .degree)), approximationTolerance: length(1e-7))
        // A quarter turn about +Z takes the corner (-2, -2) mm from the centroid to (2, -2) mm.
        #expect(hasVertex(try evaluate(turned), Point3D(x: 0.012, y: -0.002, z: 0)))

        let document = try turned.build(name: "pipe")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func anOffCentreCircleIsHollowedToItsWall() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let circle = try builder.sketch(on: .xy) { sketch in
            _ = sketch.circle(center: point(0.02, 0.02), radius: length(0.004))
        }.featureID
        _ = try builder.pipe(along: try path(in: &builder), profile: .profile(ProfileReference(featureID: circle)),
                             thickness: length(0.001), approximationTolerance: length(1e-7))
        let evaluated = try evaluate(builder)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - Double.pi * (0.004 * 0.004 - 0.003 * 0.003) * 0.05) < 1e-12)
        // The ring stands about the path's start.
        let start = evaluated.brep.vertices.values.map(\.point).filter { abs($0.z) < 1e-9 }
        #expect(start.isEmpty == false)
        #expect(start.allSatisfy { point in
            let radius = ((point.x - 0.01) * (point.x - 0.01) + point.y * point.y).squareRoot()
            return abs(radius - 0.004) < 1e-9 || abs(radius - 0.003) < 1e-9
        })
    }

    @Test(.timeLimit(.minutes(2)))
    func aFaceStandsAcrossAPathAlongAnotherAxis() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let evaluatedBox = try evaluate(builder)
        let key = try #require(evaluatedBox.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = evaluatedBox.brep.faces[id],
                  case let .plane(plane) = evaluatedBox.brep.geometry.surfaces[face.surfaceID] else { return false }
            return (face.orientation == .forward ? plane.normal : plane.normal * -1).z > 0.99
        }?.key)
        let top = SectionReference.face(FaceSectionReference(featureID: box, face: try builder.stableSubshape(key), bodyRole: .body))
        // A 30 mm line along +X from (100 mm, 0, 0): the face's +Z normal turns onto +X.
        let line = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(0.1, 0), to: point(0.13, 0))
        }.featureID
        _ = try builder.pipe(along: line, profile: top, approximationTolerance: length(1e-7))
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 2)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 + 0.02 * 0.02 * 0.03)) < 1e-12)
        let cap = evaluated.brep.vertices.values.map(\.point).filter { abs($0.x - 0.1) < 1e-9 }
        #expect(cap.count == 4)
        #expect(cap.allSatisfy { abs(abs($0.y) - 0.01) < 1e-9 && abs(abs($0.z) - 0.01) < 1e-9 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aHollowSectionWithHolesSweepsARingPerLoopAndABothSizedPipeIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let washer = try builder.sketch(on: .xy) { sketch in
            _ = sketch.circle(center: point(0, 0), radius: length(0.004))
            _ = sketch.circle(center: point(0, 0), radius: length(0.002))
        }.featureID
        let line = try path(in: &builder)
        var both = builder
        _ = try builder.pipe(along: line, profile: .profile(ProfileReference(featureID: washer)),
                             thickness: length(0.0005), approximationTolerance: length(1e-7))
        // The washer's outline walls inward and its hole outward: two rings, one body.
        let evaluated = try evaluate(builder)
        #expect(evaluated.brep.bodies.count == 1)
        let rings = Double.pi * (0.004 * 0.004 - 0.0035 * 0.0035 + 0.0025 * 0.0025 - 0.002 * 0.002)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - rings * 0.05) < 1e-12)
        // Cutting a 20 mm block at the origin, both rings take their material away where they pass
        // through it: the half of them at y ≥ 0 over its 20 mm of height.
        var cut = both
        let block = try cut.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        _ = try cut.pipe(along: line, profile: .profile(ProfileReference(featureID: washer)), thickness: length(0.0005),
                         booleanOperation: .difference, targets: [block], approximationTolerance: length(1e-7))
        let cutBlock = try evaluate(cut)
        #expect(abs(try cutBlock.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 - rings / 2 * 0.02)) < 1e-12)
        var intersecting = both
        let target = try intersecting.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        _ = try intersecting.pipe(along: line, profile: .profile(ProfileReference(featureID: washer)), thickness: length(0.0005),
                                  booleanOperation: .intersect, targets: [target], approximationTolerance: length(1e-7))
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try intersecting.build(name: "pipe"))
        }
        #expect(throws: KernelError.self) {
            _ = try both.pipe(along: line, diameter: length(0.01), profile: .profile(ProfileReference(featureID: washer)),
                              approximationTolerance: length(1e-7))
        }
    }
}
