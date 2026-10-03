import Foundation
import Testing
@testable import SwiftCAD

/// A pipe along a closed path closes into a ring with no caps (Plasticity's Pipe along a loop):
/// the section moves round the path with its frame, the turn the frame comes back with taken out,
/// and the last row of the tube is its first.
@Suite("Pipe along a closed path")
struct ClosedPathPipeTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(3)))
    func aCircularPathMakesATorus() throws {
        let (bigR, r, allowance) = (0.02, 0.002, 1e-6)
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let path = try builder.sketch(on: .xy) { _ = $0.circle(center: SketchPoint(x: length(0), y: length(0)), radius: length(bigR)) }.featureID
        _ = try builder.pipe(along: path, diameter: length(2 * r), approximationTolerance: length(allowance))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "ring"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        // Pappus: 2π R · π r², within the allowance over the tube's surface.
        let pathLength = 2 * Double.pi * bigR
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - Double.pi * r * r * pathLength) <= 2 * Double.pi * r * pathLength * allowance + 1e-12, "\(volume)")
    }

    @Test(.timeLimit(.minutes(3)))
    func aLoopLeavingItsPlaneClosesItsFrame() throws {
        // A loop rising and falling as it goes round: the frame comes back turned, which the
        // twist law takes out so the tube closes on itself.
        let (bigR, h, r, allowance) = (0.02, 0.008, 0.002, 1e-6)
        let points = [Point3D(x: bigR, y: 0, z: 0), Point3D(x: 0, y: bigR, z: h), Point3D(x: -bigR, y: 0, z: 0), Point3D(x: 0, y: -bigR, z: -h)]
        let tangents = [Vector3D(x: 0, y: 1, z: 0.3), Vector3D(x: -1, y: 0, z: 0), Vector3D(x: 0, y: -1, z: -0.3), Vector3D(x: 1, y: 0, z: 0)]
        let reach = 0.55 * bigR
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let path = FeatureID()
        try builder.append(id: path, name: "Loop", operation: .spatialPath(SpatialPathFeature(kind: .bezier, knots: zip(points, tangents).map { point, tangent in
            SpatialPathKnot(position: point, incoming: tangent * -reach, outgoing: tangent * reach, mode: .symmetric)
        }, isClosed: true)))
        _ = try builder.pipe(along: path, diameter: length(2 * r), approximationTolerance: length(allowance))
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "loop"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        // The tube's volume is its section times the path's length.
        func point(_ segment: Int, _ t: Double) -> Point3D {
            let (p0, p3) = (points[segment], points[(segment + 1) % 4])
            let p1 = p0 + tangents[segment] * reach, p2 = p3 + tangents[(segment + 1) % 4] * -reach
            let u = 1 - t
            return Point3D.origin + (p0 - .origin) * (u * u * u) + (p1 - .origin) * (3 * u * u * t) + (p2 - .origin) * (3 * u * t * t) + (p3 - .origin) * (t * t * t)
        }
        var pathLength = 0.0
        for segment in 0..<4 {
            var previous = point(segment, 0)
            for step in 1...4096 {
                let next = point(segment, Double(step) / 4096)
                pathLength += (next - previous).length
                previous = next
            }
        }
        let volume = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(volume - Double.pi * r * r * pathLength) <= 2 * Double.pi * r * pathLength * allowance + 1e-11, "\(volume)")
    }
}
