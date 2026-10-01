import Foundation
import Testing
import CADCore
import CADExchange
import CADGeometry
import CADIR
import CADTopology
@testable import SwiftCAD

/// Fillet Shell's chamfer modes: Offset cuts where each face offset by the distance meets the
/// other, Apex measures the distance along each face, and an angle sets the far contact from the
/// distance along the reference face, which Flip swaps.
@Suite("Chamfer modes")
struct ChamferModeTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func degrees(_ value: Double) -> CADExpression { .constant(.angle(value, unit: .degree)) }

    /// A regular hexagonal prism of 10 mm sides, 20 mm tall, with one upright edge chamfered.
    private func hexagon(mode: ChamferMode, d: Double) throws -> Double {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let corners = (0..<6).map { k in (0.01 * cos(Double(k) * .pi / 3), 0.01 * sin(Double(k) * .pi / 3)) }
        let sketch = try builder.sketch(on: .xy) { sketch in
            for (start, end) in zip(corners, corners.dropFirst() + corners.prefix(1)) {
                _ = sketch.line(from: SketchPoint(x: length(start.0), y: length(start.1)), to: SketchPoint(x: length(end.0), y: length(end.1)))
            }
        }.featureID
        let prism = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "hex"))
        let side = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == prism, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.x - 0.01) < 1e-12 && abs($0.y) < 1e-12 }
        }?.key)
        _ = try builder.chamfer(target: prism, edges: [try builder.stableSubshape(side)], distance: length(d), mode: mode)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "hex"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return try evaluated.brep.volume(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(2)))
    func offsetAndApexChamfersDifferAcrossAHexagonsEdge() throws {
        let d = 0.002
        let alpha = 2 * Double.pi / 3
        let solid = 3 * 3.0.squareRoot() / 2 * 0.01 * 0.01 * 0.02
        // Apex: the triangle of two d sides at α; Offset: of two d / sin α sides.
        let apex = try hexagon(mode: .apex, d: d)
        #expect(abs(apex - (solid - d * d * sin(alpha) / 2 * 0.02)) < 5e-12, "\(apex)")
        let offset = try hexagon(mode: .offset, d: d)
        #expect(abs(offset - (solid - d * d / (2 * sin(alpha)) * 0.02)) < 5e-12, "\(offset)")
    }

    /// A 20 mm box's top edge along X at y = 0 chamfered by `d` at 30°; the volume and the top face's area.
    private func angled(flipped: Bool, d: Double) throws -> (volume: Double, top: Double) {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let edge = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == box, case let .edge(id) = value, let edge = before.brep.edges[id],
                  let start = before.brep.vertices[edge.startVertexID]?.point,
                  let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
            return [start, end].allSatisfy { abs($0.y) < 1e-12 && abs($0.z - 0.02) < 1e-12 }
        }?.key)
        _ = try builder.chamfer(target: box, edges: [try builder.stableSubshape(edge)], distance: length(d),
                                angle: degrees(30), flipped: flipped)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let top = try #require(evaluated.brep.faces.first { _, face in
            guard case let .plane(plane)? = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            return abs(abs(plane.normal.z) - 1) < 1e-12 && abs(plane.origin.z - 0.02) < 1e-12
        }?.key)
        return (try evaluated.brep.volume(tolerance: .standard), try evaluated.brep.faceAreaMeasurement(of: top, tolerance: .standard).area)
    }

    @Test(.timeLimit(.minutes(2)))
    func anAngledChamferTakesTheDistanceAlongItsReferenceFaceAndFlipSwapsIt() throws {
        let (s, d) = (0.02, 0.002)
        // The far contact where the section leaves the reference face at 30° across the right angle.
        let e = d * sin(Double.pi / 6) / sin(Double.pi / 2 + Double.pi / 6)
        let plain = try angled(flipped: false, d: d), flipped = try angled(flipped: true, d: d)
        for result in [plain, flipped] {
            #expect(abs(result.volume - (s * s * s - d * e / 2 * s)) < 5e-12, "\(result.volume)")
        }
        // One cuts d from the top face and the other e: the reference face swaps.
        let cuts = [plain.top, flipped.top].map { (s * s - $0) / s }.sorted()
        #expect(abs(cuts[0] - e) < 1e-9 && abs(cuts[1] - d) < 1e-9, "\(cuts)")
    }

    @Test(.timeLimit(.minutes(2)))
    func limitPointsChamferOnlyTheirStretchOfTheEdge() throws {
        let (s, d) = (0.02, 0.002)
        let e = d * sin(Double.pi / 6) / sin(Double.pi / 2 + Double.pi / 6)
        for (limits, angle) in [(EdgeBlendLimits(start: 0.25, end: 0.75), nil as Double?), (EdgeBlendLimits(start: 0, end: 0.5), 30)] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let box = try builder.box(width: length(s), depth: length(s), height: length(s))
            let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
            let edge = try #require(before.subshapes.entries.first { key, value in
                guard key.featureID == box, case let .edge(id) = value, let edge = before.brep.edges[id],
                      let start = before.brep.vertices[edge.startVertexID]?.point,
                      let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
                return [start, end].allSatisfy { abs($0.y) < 1e-12 && abs($0.z - s) < 1e-12 }
            }?.key)
            _ = try builder.chamfer(target: box, edges: [try builder.stableSubshape(edge)], distance: length(d),
                                    angle: angle.map(degrees), limits: limits)
            let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
            try cut.brep.validate(level: .volumetric, tolerance: .standard)
            // The section's triangle along the limited stretch only, the ends flat.
            let triangle = angle == nil ? d * d / 2 : d * e / 2
            let volume = try cut.brep.volume(tolerance: .standard)
            #expect(abs(volume - (s * s * s - triangle * (limits.end - limits.start) * s)) < 5e-12, "\(limits): \(volume)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func chamferModesRoundTripThroughTheNativePackage() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try builder.box(width: length(0.02), depth: length(0.02), height: length(0.02))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "box"))
        let edges = try evaluated.subshapes.entries.filter { key, value in
            guard key.featureID == box, case .edge = value else { return false }
            return true
        }.map(\.key).sorted().prefix(2).map { try builder.stableSubshape($0) }
        _ = try builder.chamfer(target: box, edges: [edges[0]], distance: length(0.001), mode: .apex)
        _ = try builder.chamfer(target: box, edges: [edges[1]], distance: length(0.001), angle: degrees(40), flipped: true,
                                limits: EdgeBlendLimits(start: 0.1, end: 0.9))
        let document = try builder.build(name: "box")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        #expect(try store.loadDocument(from: BorrowedBytes(sink.bytes)).designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func anAngledChamferOfACylindersRimIsAConeBand() throws {
        let (radius, d) = (0.01, 0.002)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sketch = try builder.sketch(on: .xy) { sketch in
            _ = sketch.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(radius))
        }.featureID
        let cylinder = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(0.02))
        let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "c"))
        let rim = try #require(before.subshapes.entries.first { key, value in
            guard key.featureID == cylinder, case let .edge(id) = value, let edge = before.brep.edges[id],
                  case .circle? = before.brep.geometry.curves[edge.curveID],
                  let start = before.brep.vertices[edge.startVertexID]?.point else { return false }
            return abs(start.z - 0.02) < 1e-12
        }?.key)
        _ = try builder.chamfer(target: cylinder, edges: [try builder.stableSubshape(rim)], distance: length(d), angle: degrees(30))
        let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "c"))
        try cut.brep.validate(level: .volumetric, tolerance: .standard)
        // The cap is the reference: d across it, e down the wall; Pappus about the axis at d/3 in.
        let e = d * sin(Double.pi / 6) / sin(Double.pi / 2 + Double.pi / 6)
        let expected = Double.pi * radius * radius * 0.02 - d * e / 2 * 2 * Double.pi * (radius - d / 3)
        let volume = try cut.brep.volume(tolerance: .standard)
        #expect(abs(volume - expected) < 5e-12, "\(volume) vs \(expected)")
    }

    @Test(.timeLimit(.minutes(2)))
    func aDsCornerBetweenItsFlatAndItsArcChamfersByOffsetOrApex() throws {
        let (big, height, d) = (0.01, 0.01, 0.002)
        let solid = Double.pi * big * big / 2 * height
        for mode in [ChamferMode.offset, .apex] {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let sketch = try builder.sketch(on: .xy) { sketch in
                _ = sketch.arc(center: SketchPoint(x: length(0), y: length(0)), radius: length(big),
                               startAngle: degrees(0), endAngle: degrees(180))
                _ = sketch.line(from: SketchPoint(x: length(-big), y: length(0)), to: SketchPoint(x: length(big), y: length(0)))
            }.featureID
            let shape = try builder.extrude(ProfileReference(featureID: sketch, profileIndex: 0), distance: length(height))
            let before = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
            let key = try #require(before.subshapes.entries.first { key, value in
                guard key.featureID == shape, case let .edge(id) = value, let edge = before.brep.edges[id],
                      let start = before.brep.vertices[edge.startVertexID]?.point,
                      let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
                return [start, end].allSatisfy { abs($0.x - big) < 1e-12 && abs($0.y) < 1e-12 }
            }?.key)
            var both = builder
            _ = try builder.chamfer(target: shape, edges: [try builder.stableSubshape(key)], distance: length(d), mode: mode)
            let cut = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "d"))
            try cut.brep.validate(level: .volumetric, tolerance: .standard)
            // The corner cut off by the chord between the contacts, by Green's theorem: the arc from
            // the corner to the arc's contact, the chord back to the flat's.
            let removed: Double
            if mode == .offset {
                // Each face's offset by d meets the other: (r − d, 0) on the flat, (√(r² − d²), d) on the arc.
                removed = big * big * asin(d / big) / 2 - (big - d) * d / 2
            } else {
                // d from the corner along each: the arc's contact turned 2·asin(d / 2r).
                let phi = 2 * asin(d / (2 * big))
                removed = big * big * phi / 2 - (big - d) * big * sin(phi) / 2
            }
            let volume = try cut.brep.volume(tolerance: .standard)
            #expect(abs(volume - (solid - removed * height)) < 5e-12, "\(mode): \(volume)")
            // Both corners together are cut in turn, each removing as much.
            let left = try #require(before.subshapes.entries.first { key, value in
                guard key.featureID == shape, case let .edge(id) = value, let edge = before.brep.edges[id],
                      let start = before.brep.vertices[edge.startVertexID]?.point,
                      let end = before.brep.vertices[edge.endVertexID]?.point else { return false }
                return [start, end].allSatisfy { abs($0.x + big) < 1e-12 && abs($0.y) < 1e-12 }
            }?.key)
            _ = try both.chamfer(target: shape, edges: [try both.stableSubshape(key), try both.stableSubshape(left)],
                                 distance: length(d), mode: mode)
            let twice = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try both.build(name: "d"))
            try twice.brep.validate(level: .volumetric, tolerance: .standard)
            let bothVolume = try twice.brep.volume(tolerance: .standard)
            #expect(abs(bothVolume - (solid - 2 * removed * height)) < 5e-12, "\(mode): \(bothVolume)")
        }
    }

}
