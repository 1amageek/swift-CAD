import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A circular rim between a planar cap and a coaxial cone rounds into a torus band, or chamfers
/// into a cone band, all the way round: a cone's base (cut), the same cone turned onto an oblique
/// axis with its seam turned, a drafted circle's top (its wall the analytic cone), and a frustum
/// standing on a disc (filled). Each volume is the body's
/// less (or plus) the corner region of the meridian swept about the axis (Pappus).
@Suite("Conical rim blends")
struct ConicalRimBlendTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    /// A meridian point or direction: distance from the axis, and height along the cap's normal.
    private typealias Meridian = (radial: Double, height: Double)

    /// The corner region a section leaves between the rim `corner`, the cap direction `cap` and the
    /// cone's generator `wall` (unit meridian directions from the corner): its area and its
    /// centroid's distance from the axis. A round of `radius` leaves the kite to the ball's centre
    /// less the ball's sector; a chamfer the triangle to its contacts, `distance / sin α` along each.
    private func cornerRegion(corner: Meridian, cap: Meridian, wall: Meridian, round radius: Double?, chamfer distance: Double?)
        -> (area: Double, radial: Double) {
        let angle = acos(cap.radial * wall.radial + cap.height * wall.height)
        if let distance {
            let along = distance / sin(angle)
            let area = 0.5 * along * along * sin(angle)
            let radial = corner.radial + (cap.radial + wall.radial) * along / 3
            return (area, radial)
        }
        let r = radius ?? 0
        let along = r / tan(angle / 2)
        let bisector = (radial: cap.radial + wall.radial, height: cap.height + wall.height)
        let norm = (bisector.radial * bisector.radial + bisector.height * bisector.height).squareRoot()
        let reach = r / sin(angle / 2)
        let center = (radial: corner.radial + bisector.radial / norm * reach, height: corner.height + bisector.height / norm * reach)
        let capContact = corner.radial + cap.radial * along
        let wallContact = corner.radial + wall.radial * along
        // The kite: two right triangles of legs `along` and `r`, corner–contact–centre.
        let triangle = 0.5 * along * r
        let kiteMoment = triangle * (corner.radial + capContact + center.radial) / 3
            + triangle * (corner.radial + wallContact + center.radial) / 3
        // The sector of the ball between the contacts, opening toward the corner.
        let sweep = Double.pi - angle
        let sector = 0.5 * r * r * sweep
        let toCorner = -bisector.radial / norm
        let sectorRadial = center.radial + toCorner * 4 * r * sin(sweep / 2) / (3 * sweep)
        let area = 2 * triangle - sector
        return (area, (kiteMoment - sector * sectorRadial) / area)
    }

    private func unit(_ radial: Double, _ height: Double) -> Meridian {
        let length = (radial * radial + height * height).squareRoot()
        return (radial / length, height / length)
    }

    /// The edges on the circle of `radius` about `axis` through `center`.
    private func rimEdges(of feature: FeatureID, center: Point3D, axis: Vector3D, radius: Double,
                          in evaluated: EvaluatedDocument, builder: DocumentBuilder) throws -> [StableSubshapeReference] {
        try evaluated.subshapes.entries.compactMap { key, value -> SubshapeID? in
            guard key.featureID == feature, case let .edge(id) = value, let edge = evaluated.brep.edges[id],
                  let start = evaluated.brep.vertices[edge.startVertexID]?.point,
                  let end = evaluated.brep.vertices[edge.endVertexID]?.point else { return nil }
            func onRim(_ point: Point3D) -> Bool {
                let offset = point - center
                return abs(offset.dot(axis)) < 1e-9 && abs((offset - axis * offset.dot(axis)).length - radius) < 1e-9
            }
            return onRim(start) && onRim(end) ? key : nil
        }.map { try builder.stableSubshape($0) }
    }

    @Test(.timeLimit(.minutes(4)), arguments: [(false, false), (true, false), (false, true)])
    func aConesBaseRoundsOrChamfersAllRound(tilted: Bool, chamfers: Bool) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let root = 1 / 3.0.squareRoot()
        let axis = tilted ? Vector3D(x: root, y: root, z: root) : .unitZ
        let reference = tilted ? Vector3D(x: 1 / 2.0.squareRoot(), y: -1 / 2.0.squareRoot(), z: 0) : .unitX
        // A cone of 10 mm base radius, 20 mm high, its apex at the origin and its base 20 mm up the axis.
        let cone = try builder.cone(placement: PrimitivePlacement(origin: .origin, axis: axis, referenceDirection: reference),
                                    baseRadius: length(0.01), height: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "cone"))
        let rim = try rimEdges(of: cone, center: .origin + axis * 0.02, axis: axis, radius: 0.01, in: before, builder: builder)
        #expect(rim.count == 4)
        if chamfers {
            _ = try builder.chamfer(target: cone, edges: [rim[0]], distance: length(0.002))
        } else {
            _ = try builder.fillet(target: cone, edges: [rim[0]], radius: length(0.002))
        }
        let after = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "cone"))
        try after.brep.validate(level: .volumetric, tolerance: .standard)
        let region = cornerRegion(corner: (0.01, 0), cap: (-1, 0), wall: unit(-0.01, -0.02),
                                  round: chamfers ? nil : 0.002, chamfer: chamfers ? 0.002 : nil)
        let expected = Double.pi * 0.01 * 0.01 * 0.02 / 3 - 2 * Double.pi * region.radial * region.area
        let volume = try after.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 1e-15, "\(volume) vs \(expected)")
        // The cap, the cone's four quarters and the band's four quarters.
        #expect(after.brep.faces.count == 9)
    }

    @Test(.timeLimit(.minutes(4)), arguments: [false, true])
    func aFrustumStandingOnADiscFillsItsFoot(chamfers: Bool) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A disc 20 mm in radius and 10 mm thick, a frustum from 10 mm to 5 mm in radius standing
        // 20 mm on it, revolved as one body.
        let outline: [(Double, Double)] = [(0, 0), (0.02, 0), (0.02, 0.01), (0.01, 0.01), (0.005, 0.03), (0, 0.03)]
        let sketch = try builder.sketch(on: .zx) { sketch in
            for (start, end) in zip(outline, outline.dropFirst() + outline.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: self.length(start.1), y: self.length(start.0)),
                                to: SketchPoint(x: self.length(end.1), y: self.length(end.0)))
            }
        }.featureID
        let body = try builder.revolve(ProfileReference(featureID: sketch, profileIndex: 0), axis: RevolveAxis(origin: .origin, direction: .unitZ),
                                       angle: .constant(.angle(360, unit: .degree)))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "boss"))
        let rim = try rimEdges(of: body, center: Point3D(x: 0, y: 0, z: 0.01), axis: .unitZ, radius: 0.01, in: before, builder: builder)
        #expect(rim.isEmpty == false)
        if chamfers {
            _ = try builder.chamfer(target: body, edges: [rim[0]], distance: length(0.002))
        } else {
            _ = try builder.fillet(target: body, edges: [rim[0]], radius: length(0.002))
        }
        let after = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "boss"))
        try after.brep.validate(level: .volumetric, tolerance: .standard)
        let region = cornerRegion(corner: (0.01, 0), cap: (1, 0), wall: unit(-0.005, 0.02),
                                  round: chamfers ? nil : 0.002, chamfer: chamfers ? 0.002 : nil)
        let disc = Double.pi * 0.02 * 0.02 * 0.01
        let frustum = Double.pi * 0.02 / 3 * (0.01 * 0.01 + 0.01 * 0.005 + 0.005 * 0.005)
        let expected = disc + frustum + 2 * Double.pi * region.radial * region.area
        let volume = try after.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 1e-15, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(4)), arguments: [false, true])
    func aDraftedCirclesTopRimRoundsOrChamfers(chamfers: Bool) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // A circle of 10 mm radius extruded 10 mm with a 10° draft: a frustum whose wall is a cone.
        let sketch = try builder.sketch(on: .xy) { $0.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(0.01)) }.featureID
        let boss = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.01),
                                       draftAngle: .constant(.angle(10, unit: .degree)))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "boss"))
        let draft = 10 * Double.pi / 180
        let top = 0.01 - 0.01 * tan(draft)
        let rim = try rimEdges(of: boss, center: Point3D(x: 0, y: 0, z: 0.01), axis: .unitZ, radius: top, in: before, builder: builder)
        #expect(rim.isEmpty == false)
        if chamfers {
            _ = try builder.chamfer(target: boss, edges: [rim[0]], distance: length(0.001))
        } else {
            _ = try builder.fillet(target: boss, edges: [rim[0]], radius: length(0.001))
        }
        let after = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "boss"))
        try after.brep.validate(level: .volumetric, tolerance: .standard)
        let region = cornerRegion(corner: (top, 0), cap: (-1, 0), wall: (sin(draft), -cos(draft)),
                                  round: chamfers ? nil : 0.001, chamfer: chamfers ? 0.001 : nil)
        let frustum = Double.pi * 0.01 / 3 * (0.01 * 0.01 + 0.01 * top + top * top)
        let expected = frustum - 2 * Double.pi * region.radial * region.area
        let volume = try after.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 1e-15, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aRoundWiderThanTheBaseIsRefused() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let cone = try builder.cone(baseRadius: length(0.01), height: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "cone"))
        let rim = try rimEdges(of: cone, center: Point3D(x: 0, y: 0, z: 0.02), axis: .unitZ, radius: 0.01, in: before, builder: builder)
        _ = try builder.fillet(target: cone, edges: [rim[0]], radius: length(0.008))
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "cone"))
        }
    }
}
