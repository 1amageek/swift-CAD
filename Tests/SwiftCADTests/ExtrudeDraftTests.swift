import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A drafted extrusion narrows its section along the extrusion by the draft angle, one taper
/// running through the sketch plane: a rectangle into a frustum of planes, a circle into a cone,
/// both sides of a symmetric extrusion alike; an oblique drafted extrusion is refused.
@Suite("Extrude draft")
struct ExtrudeDraftTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func degrees(_ value: Double) -> CADExpression { .constant(.angle(value, unit: .degree)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "draft"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    /// ∫ (w − 2ht)(d − 2ht) dh over [lower, upper]: the drafted rectangle's volume.
    private func rectangleVolume(width w: Double, depth d: Double, tangent t: Double, from lower: Double, to upper: Double) -> Double {
        func antiderivative(_ h: Double) -> Double { w * d * h - (w + d) * t * h * h + 4.0 / 3.0 * t * t * h * h * h }
        return antiderivative(upper) - antiderivative(lower)
    }

    @Test(.timeLimit(.minutes(2)))
    func aRectangleNarrowsIntoAFrustumOfPlanes() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.02), height: length(0.01)) }
        _ = try builder.extrude(profile, distance: length(0.01), draftAngle: degrees(5))
        let evaluated = try evaluate(builder)
        let t = tan(5 * Double.pi / 180)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - rectangleVolume(width: 0.02, depth: 0.01, tangent: t, from: 0, to: 0.01)) < 1e-12)
        // Every wall leans in by the draft: its outward normal climbs by the angle's sine.
        let walls = evaluated.brep.faces.values.compactMap { face -> Vector3D? in
            guard case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID], abs(plane.normal.z) < 0.9 else { return nil }
            return face.orientation == .forward ? plane.normal : plane.normal * -1
        }
        #expect(walls.count == 4)
        #expect(walls.allSatisfy { abs($0.z - sin(5 * Double.pi / 180)) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func aSymmetricExtrusionTapersStraightThroughItsSketchPlane() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.02), height: length(0.01)) }
        _ = try builder.extrude(profile, distance: length(0.01), direction: .symmetric, draftAngle: degrees(5))
        let evaluated = try evaluate(builder)
        let t = tan(5 * Double.pi / 180)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - rectangleVolume(width: 0.02, depth: 0.01, tangent: t, from: -0.005, to: 0.005)) < 1e-12)
        #expect(evaluated.brep.faces.count == 6)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleNarrowsIntoACone() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.005)) }
        _ = try builder.extrude(profile, distance: length(0.01), draftAngle: degrees(10))
        let evaluated = try evaluate(builder)
        let t = tan(10 * Double.pi / 180)
        let (r0, r1, h) = (0.005, 0.005 - 0.01 * t, 0.01)
        let cone = Double.pi / 3 * h * (r0 * r0 + r0 * r1 + r1 * r1)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - cone) < 1e-12)
        // The top cap's rim is the narrowed circle.
        let top = evaluated.brep.vertices.values.map(\.point).filter { abs($0.z - h) < 1e-12 }
        #expect(top.isEmpty == false && top.allSatisfy { abs(Vector3D(x: $0.x, y: $0.y, z: 0).length - r1) < 1e-12 })
    }

    @Test(.timeLimit(.minutes(2)))
    func anObliqueDraftedExtrusionIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.02), height: length(0.01)) }
        _ = try builder.extrude(profile, distance: length(0.01), direction: .vector(try Vector3D(x: 1, y: 0, z: 1).normalized(tolerance: 1e-12)), draftAngle: degrees(5))
        #expect(throws: (any Error).self) { _ = try evaluate(builder) }
    }
}

/// A thin extrusion walls its section in: a rectangle into a rectangular tube open at both ends, a
/// circle into a round tube, drafted like a solid extrusion when it is drafted.
@Suite("Extrude wall thickness")
struct ExtrudeWallThicknessTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "wall"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    @Test(.timeLimit(.minutes(2)))
    func aRectangleBecomesATubeOfTheThickness() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.02), height: length(0.01)) }
        _ = try builder.extrude(profile, distance: length(0.01), thickness: length(0.001))
        let evaluated = try evaluate(builder)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (0.02 * 0.01 - 0.018 * 0.008) * 0.01) < 1e-12)
        // Four outer walls, four inner, and the two ring caps.
        #expect(evaluated.brep.faces.count == 10)
    }

    @Test(.timeLimit(.minutes(2)))
    func aCircleBecomesARoundTube() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.005)) }
        _ = try builder.extrude(profile, distance: length(0.01), thickness: length(0.001))
        let evaluated = try evaluate(builder)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - Double.pi * (0.005 * 0.005 - 0.004 * 0.004) * 0.01) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aThicknessWiderThanTheSectionIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: length(0.02), height: length(0.01)) }
        _ = try builder.extrude(profile, distance: length(0.01), thickness: length(0.006))
        #expect(throws: (any Error).self) { _ = try evaluate(builder) }
    }
}

/// A planar face of a body extrudes like a profile, along its outward normal: a box's top grows a
/// block as a new body, or grows the box itself when united with it, drafted like any section; the
/// face section survives a native round trip.
@Suite("Extrude face")
struct ExtrudeFaceTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "face"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    private func top(of box: FeatureID, in builder: DocumentBuilder) throws -> StableSubshapeReference {
        let evaluated = try evaluate(builder)
        let key = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            let outward = face.orientation == .forward ? plane.normal : plane.normal * -1
            return outward.z > 0.99
        }?.key)
        return try builder.stableSubshape(key)
    }

    @Test(.timeLimit(.minutes(2)))
    func aBoxsTopGrowsABlockOrTheBoxItself() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let face = try top(of: box, in: builder)
        var apart = builder
        _ = try apart.extrude(face: face, of: box, distance: length(0.01))
        let separate = try evaluate(apart)
        #expect(separate.brep.bodies.count == 2)
        #expect(abs(try separate.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 + 0.02 * 0.02 * 0.01)) < 1e-12)

        _ = try builder.extrude(face: face, of: box, distance: length(0.01), operation: .union, targets: [box])
        let grown = try evaluate(builder)
        let zs = grown.brep.vertices.values.map(\.point.z)
        #expect(abs((zs.max() ?? 0) - (zs.min() ?? 0) - 0.03) < 1e-12)
        #expect(abs(try grown.brep.volume(tolerance: .standard) - 0.02 * 0.02 * 0.03) < 1e-12)

        let document = try builder.build(name: "face")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func aDraftedFaceExtrusionTapersLikeAProfile() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let face = try top(of: box, in: builder)
        _ = try builder.extrude(face: face, of: box, distance: length(0.01), draftAngle: .constant(.angle(5, unit: .degree)))
        let evaluated = try evaluate(builder)
        let t = tan(5 * Double.pi / 180)
        // ∫₀^0.01 (0.02 − 2ht)² dh beside the 20 mm box.
        let exact = 0.02 * 0.02 * 0.01 - (0.02 + 0.02) * t * 0.01 * 0.01 + 4.0 / 3.0 * t * t * 0.01 * 0.01 * 0.01
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 + exact)) < 1e-12)
    }
}
