import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
import SwiftCAD

/// Delete Redundant Topology merges faces on one surface and edges on one curve, the shape
/// unchanged: a box's split top and the edges the split cut are whole again, a split sheet is
/// one face again, and a body with nothing redundant is refused.
@Suite("Delete Redundant Topology")
struct RedundantTopologyTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let side = 0.02

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "redundant"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func body(of featureID: FeatureID, in evaluated: EvaluatedDocument) throws -> Body {
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: featureID, role: "body", ordinal: 0)],
              let body = evaluated.brep.bodies[bodyID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, tolerance: .standard, message: "No body.")
        }
        return body
    }

    private func faceCount(_ body: Body, in evaluated: EvaluatedDocument) -> Int {
        body.shellIDs.reduce(0) { $0 + (evaluated.brep.shells[$1]?.faceIDs.count ?? 0) }
    }

    private func firstFace(of feature: FeatureID, in evaluated: EvaluatedDocument, builder: DocumentBuilder, where predicate: (Face, Surface3D) -> Bool) throws -> StableSubshapeReference {
        let key = try #require(evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == feature, case let .face(faceID) = value, let face = evaluated.brep.faces[faceID],
                  let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return predicate(face, surface)
        }.keys.sorted().first)
        return try builder.stableSubshape(key)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSplitTopAndTheEdgesItCutAreWholeAgain() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        let top = try firstFace(of: box, in: try evaluate(builder), builder: builder) { face, surface in
            guard case let .plane(plane) = surface else { return false }
            return (face.orientation == .forward ? plane.normal : plane.normal * -1).dot(.unitZ) > 0.99
        }
        let split = try builder.isoparam(box, face: top, direction: .v, fractions: [0.5])
        let whole = try builder.removeRedundantTopology(target: split)
        let evaluated = try evaluate(builder)
        let solid = try body(of: whole, in: evaluated)
        #expect(faceCount(solid, in: evaluated) == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - side * side * side) < 1e-12)
    }

    @Test(.timeLimit(.minutes(2)))
    func aSplitSheetIsOneFaceAgain() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: side, y: 0, z: 0)],
                            [Point3D(x: 0, y: side, z: 0.005), Point3D(x: side, y: side, z: 0)]]
        ))
        let face = try firstFace(of: sheet, in: try evaluate(builder), builder: builder) { _, _ in true }
        let split = try builder.isoparam(sheet, face: face, direction: .u, fractions: [0.25, 0.5])
        let whole = try builder.removeRedundantTopology(target: split)
        let evaluated = try evaluate(builder)
        #expect(faceCount(try body(of: whole, in: evaluated), in: evaluated) == 1)
        #expect(evaluated.brep.edges.count == 4)
    }

    @Test(.timeLimit(.minutes(2)))
    func aBodyWithNothingRedundantIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(side), depth: length(side), height: length(side))
        _ = try builder.removeRedundantTopology(target: box)
        #expect(throws: (any Error).self) {
            _ = try evaluate(builder)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aFullRevolvesQuarterFacesAreOneFaceEachWithOneSeam() throws {
        // A 10 × 20 mm rectangle 10 mm off the Z axis turned a full turn: a tube whose cylinders
        // and annuli are each four quarters, merged into four faces, each cylinder keeping one seam.
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .zx) { sketch in
            let corners = [(0.0, 0.01), (0.0, 0.02), (0.02, 0.02), (0.02, 0.01)]
            for (a, b) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(a.0), y: length(a.1)), to: SketchPoint(x: length(b.0), y: length(b.1)))
            }
        }
        let tube = try builder.revolve(profile, axis: RevolveAxis(origin: .origin, direction: .unitZ))
        let before = try evaluate(builder)
        #expect(faceCount(try body(of: tube, in: before), in: before) == 16)
        let whole = try builder.removeRedundantTopology(target: tube)
        let evaluated = try evaluate(builder)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let solid = try body(of: whole, in: evaluated)
        #expect(faceCount(solid, in: evaluated) == 4)
        let expected = Double.pi * (0.02 * 0.02 - 0.01 * 0.01) * 0.02
        #expect(abs(try evaluated.brep.volume(of: solid.id, tolerance: .standard) - expected) < 1e-12)
    }
}
