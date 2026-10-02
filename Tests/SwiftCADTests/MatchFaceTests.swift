import Foundation
import Testing
@testable import SwiftCAD

/// Match Face puts faces of a body onto another face's surface, of another body where it is
/// placed, and re-solves the faces around them; a match that collapses the body is refused.
@Suite("Match Face")
struct MatchFaceTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }

    private func box(_ builder: inout DocumentBuilder, height: Double) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        return try builder.extrude(profile, distance: millimeters(height))
    }

    private func horizontalFace(of featureID: FeatureID, in builder: DocumentBuilder, z: Double) throws -> StableSubshapeReference {
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let key = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == featureID, case let .face(id) = value, let face = evaluated.brep.faces[id],
                  case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.z) - 1) < 1e-9 && abs(plane.origin.z - z) < 1e-9
        }?.key)
        return try builder.stableSubshape(key)
    }

    private func volume(of featureID: FeatureID, in builder: DocumentBuilder) throws -> Double {
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let bodyID = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == featureID, case .body = value else { return false }
            return true
        }.flatMap { entry -> BodyID? in
            if case let .body(id) = entry.value { return id }
            return nil
        })
        return try evaluated.brep.volume(of: bodyID, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopMatchesTheTopOfATallerBody() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let short = try box(&builder, height: 10)
        let tall = try box(&builder, height: 15)
        let top = try horizontalFace(of: short, in: builder, z: 0.010)
        let reference = try horizontalFace(of: tall, in: builder, z: 0.015)
        let matched = try builder.matchFace(target: short, faces: [top], source: tall, referenceFace: reference)
        #expect(abs(try volume(of: matched, in: builder) - 0.040 * 0.020 * 0.015) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func aReferenceOnAnotherBodyIsMatchedWhereItIsPlaced() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let target = try box(&builder, height: 10)
        let other = try box(&builder, height: 10)
        let top = try horizontalFace(of: target, in: builder, z: 0.010)
        let reference = try horizontalFace(of: other, in: builder, z: 0.010)
        let matched = try builder.matchFace(
            target: target, faces: [top], source: other, referenceFace: reference,
            sourcePlacement: .translated(by: Vector3D(x: 0, y: 0, z: 0.003))
        )
        #expect(abs(try volume(of: matched, in: builder) - 0.040 * 0.020 * 0.013) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func matchingTheTopToTheBottomIsRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let target = try box(&builder, height: 10)
        let top = try horizontalFace(of: target, in: builder, z: 0.010)
        let bottom = try horizontalFace(of: target, in: builder, z: 0)
        _ = try builder.matchFace(target: target, faces: [top], source: target, referenceFace: bottom)
        #expect(throws: (any Error).self) {
            _ = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        }
    }

    /// An L prism's step (x = 10 mm) matched onto a wall placed at x = 25 mm, past its own outer
    /// wall at x = 20 mm: a push, so Grow runs into that wall as Push Face's does.
    @Test(.timeLimit(.minutes(2)), arguments: [(FaceEditGrow.moving, 10_000.0), (FaceEditGrow.fixed, 8_000.0)])
    func aStepMatchedPastItsWallGrowsByItsMode(grow: FaceEditGrow, volume: Double) throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let corners = [(0.0, 0.0), (20.0, 0.0), (20.0, 10.0), (10.0, 10.0), (10.0, 20.0), (0.0, 20.0)]
        let profile = try builder.sketch(on: .xy) { sketch in
            for k in corners.indices {
                let (a, b) = (corners[k], corners[(k + 1) % corners.count])
                _ = sketch.line(from: SketchPoint(x: millimeters(a.0), y: millimeters(a.1)), to: SketchPoint(x: millimeters(b.0), y: millimeters(b.1)))
            }
        }
        let body = try builder.extrude(profile, distance: millimeters(20))
        let wall = try box(&builder, height: 10)
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        func face(of feature: FeatureID, atX x: Double) throws -> StableSubshapeReference {
            let key = try #require(evaluated.subshapes.entries.first { key, value in
                guard key.featureID == feature, case let .face(id) = value, let face = evaluated.brep.faces[id],
                      case let .plane(plane) = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
                return abs(abs(plane.normal.x) - 1) < 1e-9 && abs(plane.origin.x - x) < 1e-9
            }?.key)
            return try builder.stableSubshape(key)
        }
        let matched = try builder.matchFace(target: body, faces: [try face(of: body, atX: 0.010)], source: wall,
                                            referenceFace: try face(of: wall, atX: 0.020),
                                            sourcePlacement: .translated(by: Vector3D(x: 0.005, y: 0, z: 0)), grow: grow)
        #expect(abs(try self.volume(of: matched, in: builder) - volume * 1e-9) < 1e-15)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTopMatchesACurvedFaceOfAnotherBody() throws {
        // Push Face's dependant offset: the 40 × 20 mm box's top (centred, y -10...10) put onto a
        // cylinder of another body lying along x (radius 30 mm, axis at y = 0, z = -15), whose
        // crown is 15 mm up.
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let target = try box(&builder, height: 10)
        // On the YZ plane sketch x is world y and sketch y is world z.
        let circle = try builder.sketch(on: .yz) { _ = $0.circle(center: SketchPoint(x: millimeters(0), y: millimeters(-15)), radius: millimeters(30)) }
        let roller = try builder.extrude(circle, distance: millimeters(40))
        let evaluated = try CADPipeline(tolerance: .standard).evaluate(builder.build())
        let curvedKey = try #require(evaluated.subshapes.entries.first { key, value in
            guard key.featureID == roller, case let .face(id) = value, let face = evaluated.brep.faces[id] else { return false }
            switch evaluated.brep.geometry.surfaces[face.surfaceID] {
            case .cylinder, .analytic(.cylinder): return true
            default: return false
            }
        }?.key)
        let top = try horizontalFace(of: target, in: builder, z: 0.010)
        let matched = try builder.matchFace(target: target, faces: [top], source: roller, referenceFace: try builder.stableSubshape(curvedKey))
        // The section under the arc z = -15 + √(900 − y²) over y -10...10, times 40 mm.
        let r = 30.0
        let arcArea = 10 * (r * r - 100).squareRoot() + r * r * asin(10 / r)
        let expected = 40 * (arcArea - 15 * 20) * 1e-9
        let volume = try volume(of: matched, in: builder)
        #expect(abs(volume - expected) < 1e-12, "\(volume) vs \(expected)")
    }
}

