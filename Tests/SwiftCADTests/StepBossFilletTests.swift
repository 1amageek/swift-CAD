import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A cylinder rising from a step: the step's top loop — the arc where the cylinder's foot meets
/// it and the straight edges falling to its sides — rounds as one (Plasticity's Y-blend video's
/// first round, with Attempt to create Y-Blend off).
@Suite("Step boss fillet")
struct StepBossFilletTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(8)))
    func aStepsTopLoopRoundsIntoTheBossRisingFromIt() throws {
        // A cylinder of radius 10 mm and a 20 × 16 mm step 15 mm high, its top at 16 mm, beside it.
        let (rc, h, r) = (0.01, 0.016, 0.002)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cylinder = try builder.cylinder(radius: length(rc), height: length(0.04))
        let step = try builder.box(placement: PrimitivePlacement(origin: Point3D(x: 0.003, y: -0.008, z: 0.001), axis: .unitZ,
                                                                 referenceDirection: .unitX),
                                   width: length(0.02), depth: length(0.016), height: length(0.015))
        let body = try builder.boolean(targets: [cylinder], tool: step, operation: .union)
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "s"))
        // The step's top loop: the two arcs of the cylinder's foot (split at its seam) and the
        // three straight edges.
        let loop = try before.subshapes.entries.filter { key, value in
            guard key.featureID == body, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let a = before.brep.vertices[edge.startVertexID]?.point,
                  let b = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return abs(a.z - h) < 1e-12 && abs(b.z - h) < 1e-12 && max(a.x, b.x) > 0.0055
        }.map { try builder.stableSubshape($0.key) }
        #expect(loop.count == 5)
        var attempt = builder
        _ = try builder.fillet(target: body, edges: loop, radius: length(r))
        let rounded = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "s"))
        try rounded.brep.validate(level: .volumetric, tolerance: .standard)
        // The bands: each straight edge's corner section r²(1 − π/4) cut away along the line its
        // centroid runs, δ in from both faces, between its ends (square at the corner patches,
        // mitred at the step's corners); the arcs' sections filled about the axis at rc + δ
        // between the meridians through the corner patches' cap points, 30° either side.
        let section = r * r * (1 - Double.pi / 4)
        let inset = r * (10 - 3 * Double.pi) / (12 - 3 * Double.pi)
        let xP = ((rc + r) * (rc + r) - (0.008 - r) * (0.008 - r)).squareRoot()
        let cut = section * (2 * (0.023 - inset - xP) + (0.016 - 2 * inset))
        let fill = section * (rc + inset) * (Double.pi / 3)
        let original = try before.brep.volume(tolerance: .standard)
        let volume = try rounded.brep.volume(tolerance: .standard)
        // The corner patches change the rest within their cells: x from the step's side at the
        // cylinder to the cap point, y from the meridian's wall contact to the side, z within r of
        // the cap — two such cells at most.
        let cell = (xP - 0.006) * (0.008 - rc * 0.5) * (2 * r)
        let corners = volume - (original - cut + fill)
        #expect(abs(corners) < 2 * cell, "\(volume) vs \(original - cut + fill): corners \(corners), cell \(cell)")
        // Each band lies the radius from its axis: the straight edges' a radius in from the side
        // and below the top, the arcs' about the tube circle a radius out from the cylinder and
        // above the top; the two other spline faces are the corner patches.
        let axes: [(Point3D) -> Double] = [
            { p in ((p.y + 0.008 - r) * (p.y + 0.008 - r) + (p.z - h + r) * (p.z - h + r)).squareRoot() },
            { p in ((p.y - 0.008 + r) * (p.y - 0.008 + r) + (p.z - h + r) * (p.z - h + r)).squareRoot() },
            { p in ((p.x - 0.023 + r) * (p.x - 0.023 + r) + (p.z - h + r) * (p.z - h + r)).squareRoot() },
            { p in
                let rho = (p.x * p.x + p.y * p.y).squareRoot()
                return ((rho - rc - r) * (rho - rc - r) + (p.z - h - r) * (p.z - h - r)).squareRoot()
            },
        ]
        var bands = 0
        var others = 0
        for face in rounded.brep.faces.values {
            guard case let .bSpline(surface)? = rounded.brep.geometry.surfaces[face.surfaceID] else { continue }
            let samples = try (1...4).flatMap { i in try (1...4).map { j in
                try surface.point(u: Double(i) / 5, v: Double(j) / 5, tolerance: .standard)
            } }
            if axes.contains(where: { axis in samples.allSatisfy { abs(axis($0) - r) < 1e-9 } }) { bands += 1 } else { others += 1 }
        }
        #expect(bands == 5 && others == 2, "\(bands) bands, \(others) others")
        // Where the step's side faces meet the cylinder, the sharp upright edges now stop r below
        // the step's top, and the cylinder's seam above the round stops r above it.
        let ends = rounded.brep.edges.values.compactMap { edge -> (Point3D, Point3D)? in
            guard case .line? = rounded.brep.geometry.curves[edge.curveID], let a = rounded.brep.vertices[edge.startVertexID]?.point,
                  let b = rounded.brep.vertices[edge.endVertexID]?.point else { return nil }
            return (a, b)
        }
        let uprights = ends.filter { a, b in abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 && abs(abs(a.y) - 0.008) < 1e-9 && abs(a.x - 0.006) < 1e-9 }
        #expect(uprights.count == 2)
        #expect(uprights.allSatisfy { abs(max($0.0.z, $0.1.z) - (h - r)) < 1e-9 })
        let seam = ends.filter { a, b in abs(a.x - rc) < 1e-9 && abs(b.x - rc) < 1e-9 && abs(a.y) < 1e-9 && min(a.z, b.z) > 0.01 }
        #expect(seam.count == 1 && seam.allSatisfy { abs(min($0.0.z, $0.1.z) - (h + r)) < 1e-9 })
        // Attempt to create Y-Blend: each corner patch three faces meeting in a Y at its middle,
        // the same surface, two more faces at each corner.
        _ = try attempt.fillet(target: body, edges: loop, radius: length(r), yBlend: true)
        let ySplit = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try attempt.build(name: "s"))
        try ySplit.brep.validate(level: .volumetric, tolerance: .standard)
        // The patches' sides follow their exact edges within an eighth of the distance tolerance,
        // so faces split along them may move the volume by that much over each patch's area.
        let yVolume = try ySplit.brep.volume(tolerance: .standard)
        #expect(abs(yVolume - volume) < 2 * (2 * r) * (2 * r) * 1e-6 / 8, "\(yVolume) vs \(volume)")
        #expect(ySplit.brep.faces.count == rounded.brep.faces.count + 4)
        // Three edges meet at each Y's middle and at the two band sections' middles its arms
        // reach, off the cap and walls.
        let middles = ySplit.brep.vertices.values.filter { vertex in
            ySplit.brep.edges.values.filter { $0.startVertexID == vertex.id || $0.endVertexID == vertex.id }.count == 3
                && vertex.point.z > h - r + 1e-6 && vertex.point.z < h + r - 1e-6 && vertex.point.x < 0.0105
        }
        #expect(middles.count == 6)
    }
}
