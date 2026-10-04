import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Reblend (Deform Solid and Sheet): a rounded block's rounded top outline bent onto a cylinder.
/// Bent with the body, each round's section is stretched with the cylinder's growing radius, so the
/// ball through a point of it no longer touches the faces it blends at its radius; reblended, the
/// rounds are recomputed on the bent faces, and every such ball touches both at the radius.
@Suite("Wrap Reblend")
struct WrapReblendTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private let radius = 0.002

    /// The block (40 × 30 mm, 5 mm round corners, 10 mm high, from the origin) with its top
    /// outline rounded at `radius`, standing on a flat sheet, bent onto a cylinder's side.
    private func bent(reblends: Bool, validates: Bool = true) throws -> BRepModel {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let (w, h, c) = (0.04, 0.03, 0.005)
        func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }
        func degrees(_ value: Double) -> CADExpression { .constant(.angle(value, unit: .degree)) }
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(c, 0), to: point(w - c, 0))
            _ = sketch.arc(center: point(w - c, c), radius: length(c), startAngle: degrees(-90), endAngle: degrees(0))
            _ = sketch.line(from: point(w, c), to: point(w, h - c))
            _ = sketch.arc(center: point(w - c, h - c), radius: length(c), startAngle: degrees(0), endAngle: degrees(90))
            _ = sketch.line(from: point(w - c, h), to: point(c, h))
            _ = sketch.arc(center: point(c, h - c), radius: length(c), startAngle: degrees(90), endAngle: degrees(180))
            _ = sketch.line(from: point(0, h - c), to: point(0, c))
            _ = sketch.arc(center: point(c, c), radius: length(c), startAngle: degrees(180), endAngle: degrees(270))
        }.featureID
        let block = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.01))
        let plain = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
        let topEdge = try #require(plain.subshapes.entries.first { key, value in
            guard key.featureID == block, case let .edge(id) = value, let edge = plain.brep.edges[id],
                  case .line? = plain.brep.geometry.curves[edge.curveID],
                  let start = plain.brep.vertices[edge.startVertexID]?.point,
                  let end = plain.brep.vertices[edge.endVertexID]?.point else { return false }
            return abs(start.z - 0.01) < 1e-12 && abs(end.z - 0.01) < 1e-12 && abs(start.y) < 1e-12 && abs(end.y) < 1e-12
        }?.key)
        let rounded = try builder.fillet(target: block, edges: [try builder.stableSubshape(topEdge)], radius: length(radius))
        let half = 0.05
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [-half, half].map { y in [-half, half].map { Point3D(x: $0, y: y, z: 0) } }
        ))
        let cylinder = try builder.cylinder(radius: length(0.1), height: length(0.2))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
        func face(of feature: FeatureID, where keep: (Surface3D) -> Bool) throws -> StableSubshapeReference {
            let key = try #require(before.subshapes.entries.filter { key, value in
                guard key.featureID == feature, case let .face(faceID) = value, let face = before.brep.faces[faceID],
                      let surface = before.brep.geometry.surfaces[face.surfaceID] else { return false }
                return keep(surface)
            }.keys.sorted().first)
            return try builder.stableSubshape(key)
        }
        let sheetFace = try face(of: sheet) { _ in true }
        let side = try face(of: cylinder) { if case .cylinder = $0 { return true }; return false }
        _ = try builder.wrap(rounded, from: sheetFace, onto: side, options: WrapOptions(reblends: reblends))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "r"))
        if validates { try evaluated.brep.validate(level: .volumetric, tolerance: .standard) }
        return evaluated.brep
    }

    /// The largest miss, over points inside every round of the bent body, of the ball of `radius`
    /// through the point (its centre `radius` in along the normal) from touching both faces it
    /// blends: |distance − radius| to the bent top and to the wall beside the round.
    private func ballMiss(_ model: BRepModel) throws -> Double {
        var uses: [EdgeID: [FaceID]] = [:]
        for face in model.faces.values {
            for loopID in face.loops {
                for coedge in model.loops[loopID]?.coedges ?? [] { uses[coedge.edgeID, default: []].append(face.id) }
            }
        }
        func edges(_ faceID: FaceID) -> [EdgeID] {
            (model.faces[faceID]?.loops ?? []).flatMap { model.loops[$0]?.coedges.map(\.edgeID) ?? [] }
        }
        func neighbours(_ faceID: FaceID) -> [FaceID] {
            edges(faceID).compactMap { edge in uses[edge]?.first { $0 != faceID } }
        }
        func surface(_ faceID: FaceID) throws -> BSplineSurface3D {
            guard let face = model.faces[faceID], case let .bSpline(surface)? = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A bent face is not a B-spline.")
            }
            return surface
        }
        // The top: the face of eight edges farthest from the cylinder's axis (z).
        let eightEdged = model.faces.keys.filter { edges($0).count == 8 }
        func reach(_ faceID: FaceID) throws -> Double {
            let s = try surface(faceID)
            let p = try s.point(u: 0.5 * (s.uKnots.first! + s.uKnots.last!), v: 0.5 * (s.vKnots.first! + s.vKnots.last!), tolerance: .standard)
            return (p.x * p.x + p.y * p.y).squareRoot()
        }
        let top = try #require(try eightEdged.max { try reach($0) < reach($1) })
        let rounds = neighbours(top)
        #expect(rounds.count == 8)
        func distance(_ point: Point3D, to s: BSplineSurface3D) throws -> Double {
            let (u0, u1, v0, v1) = (s.uKnots.first!, s.uKnots.last!, s.vKnots.first!, s.vKnots.last!)
            var best = (u: u0, v: v0, d: Double.infinity)
            for i in 0...24 {
                for j in 0...24 {
                    let (u, v) = (u0 + (u1 - u0) * Double(i) / 24, v0 + (v1 - v0) * Double(j) / 24)
                    let d = (try s.point(u: u, v: v, tolerance: .standard) - point).length
                    if d < best.d { best = (u, v, d) }
                }
            }
            var (u, v) = (best.u, best.v)
            for _ in 0..<40 {
                let g = try s.differentialGeometry(u: u, v: v, tolerance: .standard)
                let miss = point - g.position
                let (a, b, c) = (g.tangentU.dot(g.tangentU), g.tangentU.dot(g.tangentV), g.tangentV.dot(g.tangentV))
                let det = a * c - b * b
                let (p, q) = (g.tangentU.dot(miss), g.tangentV.dot(miss))
                u = min(max(u + (c * p - b * q) / det, u0), u1)
                v = min(max(v + (a * q - b * p) / det, v0), v1)
            }
            return (try s.point(u: u, v: v, tolerance: .standard) - point).length
        }
        var worst = 0.0
        for round in rounds {
            let walls = neighbours(round).filter { $0 != top && rounds.contains($0) == false }
            let wall = try #require(walls.first)
            let face = try #require(model.faces[round])
            let s = try surface(round)
            let (u0, u1, v0, v1) = (s.uKnots.first!, s.uKnots.last!, s.vKnots.first!, s.vKnots.last!)
            for i in 1...3 {
                for j in 1...3 {
                    let g = try s.differentialGeometry(u: u0 + (u1 - u0) * Double(i) / 4, v: v0 + (v1 - v0) * Double(j) / 4, tolerance: .standard)
                    let outward = g.normal * (face.orientation == .forward ? 1 : -1)
                    let center = g.position + outward * -radius
                    worst = max(worst, abs(try distance(center, to: try surface(top)) - radius),
                                abs(try distance(center, to: try surface(wall)) - radius))
                }
            }
        }
        return worst
    }

    // About twenty minutes in debug builds, nearly all of it the reblended solid's certified volume.
    @Test(.timeLimit(.minutes(40)))
    func reblendRecomputesTheRoundsOnTheBentFaces() throws {
        // The rounds bent with the body are only measured; the reblended solid is validated whole.
        let bentRounds = try ballMiss(try bent(reblends: false, validates: false))
        let reblended = try ballMiss(try bent(reblends: true))
        // Bent with the body the rounds miss by a sizeable part of their radius; reblended the
        // ball touches both faces within the fits' allowance.
        #expect(bentRounds > 1e-5, "\(bentRounds)")
        #expect(reblended < 2e-6, "\(reblended)")
    }

    @Test(.timeLimit(.minutes(2)))
    func reblendRoundTripsThroughItsEncodingAndDefaultsOff() throws {
        let options = WrapOptions(scaleU: 1.5, reblends: true)
        let decoded = try JSONDecoder().decode(WrapOptions.self, from: try JSONEncoder().encode(options))
        #expect(decoded == options && decoded.reblends)
        // A document written before Reblend existed has no such key: its fillets bend with the body.
        var object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(options)) as? [String: Any])
        object.removeValue(forKey: "reblends")
        let legacy = try JSONDecoder().decode(WrapOptions.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(legacy.reblends == false && legacy.scaleU == 1.5)
    }
}
