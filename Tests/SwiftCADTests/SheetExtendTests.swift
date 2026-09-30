import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Extend Sheet carries a sheet's open edges on: a planar sheet by the distance in its plane, a
/// B-spline sheet past its parameter boundary as its own surface continued, straight on, or
/// reflected, joined to the sheet or beside it; edges meeting at a corner are refused.
@Suite("Extend Sheet")
struct SheetExtendTests {
    private func millimeters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .millimeter)) }
    private func meters(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "extend"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        return evaluated
    }

    private func edges(of feature: FeatureID, in builder: DocumentBuilder, where predicate: (Point3D, Point3D) -> Bool) throws -> [StableSubshapeReference] {
        let evaluated = try evaluate(builder)
        return try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == feature, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let a = evaluated.brep.vertices[edge.startVertexID]?.point, let b = evaluated.brep.vertices[edge.endVertexID]?.point else { return false }
            return predicate(a, b)
        }.map(\.key).sorted().map { try builder.stableSubshape($0) }
    }

    /// The 40 × 20 mm bottom of a box, its four walls and top deleted.
    private func planarSheet(_ builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { $0.rectangle(width: millimeters(40), height: millimeters(20)) }
        let box = try builder.extrude(profile, distance: millimeters(10))
        var removed = [try builder.stableSubshape(generatedBy: box, selector: .generated(role: .endFace))]
        for index in 0..<4 { removed.append(try builder.stableSubshape(generatedBy: box, selector: .generated(role: .sideFace, index: index))) }
        return try builder.faceDelete(target: box, faces: removed)
    }

    @Test(.timeLimit(.minutes(2)))
    func aPlanarSheetGrowsInItsPlaneAndBesideItWhenAsked() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let sheet = try planarSheet(&builder)
        let right = try #require(try edges(of: sheet, in: builder) { a, b in abs(a.x - 0.020) < 1e-9 && abs(b.x - 0.020) < 1e-9 }.first)
        var joined = builder
        _ = try joined.extendSheet(target: sheet, edges: [right], distance: millimeters(5))
        let model = try evaluate(joined).brep
        #expect(model.bodies.count == 1)
        #expect(abs((model.vertices.values.map(\.point.x).max() ?? 0) - 0.025) < 1e-12)

        _ = try builder.extendSheet(target: sheet, edges: [right], distance: millimeters(5), modifies: false)
        let apart = try evaluate(builder).brep
        #expect(apart.bodies.count == 2)
    }

    @Test(.timeLimit(.minutes(2)))
    func edgesMeetingAtACornerAreRefused() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let sheet = try planarSheet(&builder)
        let right = try #require(try edges(of: sheet, in: builder) { a, b in abs(a.x - 0.020) < 1e-9 && abs(b.x - 0.020) < 1e-9 }.first)
        let top = try #require(try edges(of: sheet, in: builder) { a, b in abs(a.y - 0.010) < 1e-9 && abs(b.y - 0.010) < 1e-9 }.first)
        _ = try builder.extendSheet(target: sheet, edges: [right, top], distance: millimeters(5))
        #expect(throws: (any Error).self) { _ = try evaluate(builder) }
    }

    @Test(.timeLimit(.minutes(2)))
    func aBilinearSheetContinuesItselfPastItsBoundary() throws {
        let side = 0.02
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: side, y: 0, z: 0)],
                            [Point3D(x: 0, y: side, z: 0.005), Point3D(x: side, y: side, z: 0)]]
        ))
        let edge = try #require(try edges(of: sheet, in: builder) { a, b in abs(a.x - side) < 1e-12 && abs(b.x - side) < 1e-12 }.first)
        _ = try builder.extendSheet(target: sheet, edges: [edge], distance: meters(0.01))
        let model = try evaluate(builder).brep
        // S(u, v) is linear in u, so the extension reaches u = 1 + d / |S_u(½)| exactly.
        let speed = (Vector3D(x: side, y: 0, z: 0) * 0.5 + Vector3D(x: side, y: 0, z: -0.005) * 0.5).length
        let reach = 1 + 0.01 / speed
        let far = model.vertices.values.map(\.point).filter { abs($0.x - side * reach) < 1e-9 }
        #expect(far.count == 2)
        // At v = 1 the continued surface drops as (1 - u)·0.005 does.
        #expect(far.contains { abs($0.y - side) < 1e-9 && abs($0.z - (1 - reach) * 0.005) < 1e-9 })
    }

    @Test(.timeLimit(.minutes(2)), arguments: [SheetExtensionShape.natural, .linear, .reflective])
    func aCurvedSheetCarriesOnInEachShape(shape: SheetExtensionShape) throws {
        let s = 0.02
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A parabolic arch z = s·u·(1 - u), x = s·u, swept along y.
        let row = { (y: Double) in [Point3D(x: 0, y: y, z: 0), Point3D(x: s / 2, y: y, z: s / 2), Point3D(x: s, y: y, z: 0)] }
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [row(0), row(s)]
        ))
        let edge = try #require(try edges(of: sheet, in: builder) { a, b in abs(a.x - s) < 1e-12 && abs(b.x - s) < 1e-12 }.first)
        _ = try builder.extendSheet(target: sheet, edges: [edge], distance: meters(0.005), shape: shape)
        let model = try evaluate(builder).brep
        let far = try #require(model.vertices.values.map(\.point).filter { abs($0.y) < 1e-12 }.max { $0.x < $1.x })
        #expect(far.x > s + 1e-6)
        // Past u = 1 the arch goes on as a parabola, a tangent line, or the arch mirrored across
        // the plane perpendicular to its end tangent, (1, 0, -1)/√2 through (s, 0, 0).
        switch shape {
        case .natural: #expect(abs(far.z + (far.x - s) * far.x / s) < 1e-9)
        case .linear: #expect(abs(far.z + (far.x - s)) < 1e-9)
        case .reflective:
            let normal = Vector3D(x: 1, y: 0, z: -1) * (1 / 2.0.squareRoot())
            let mirrored = far + normal * (-2 * (far - Point3D(x: s, y: 0, z: 0)).dot(normal))
            #expect(abs(mirrored.z - mirrored.x * (s - mirrored.x) / s) < 1e-9)
            #expect(mirrored.x < s)
        }
    }
}
