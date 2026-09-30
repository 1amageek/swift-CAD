import Foundation
import Testing
import CADCore
import CADExchange
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// A pipe sweeps its circle or polygon across its path: exactly along a straight path, hollow to
/// its wall, cut to its start and end, within its allowance along a curve, and combined with
/// targets.
@Suite("Pipe")
struct PipeTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func scalar(_ value: Double) -> CADExpression { .constant(.scalar(value)) }

    private func evaluate(_ builder: DocumentBuilder) throws -> EvaluatedDocument {
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "pipe"))
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        return evaluated
    }

    /// A 50 mm line up the Z axis from the origin (sketch x is world z on the ZX plane).
    private func line(in builder: inout DocumentBuilder) throws -> FeatureID {
        try builder.sketch(on: .zx) { sketch in
            _ = sketch.line(from: SketchPoint(x: length(0), y: length(0)), to: SketchPoint(x: length(0.05), y: length(0)))
        }.featureID
    }

    @Test(.timeLimit(.minutes(2)))
    func aStraightPipeIsAnExactTubeOrPrism() throws {
        let r = 0.005, L = 0.05
        var round = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try round.pipe(along: try line(in: &round), diameter: length(2 * r), approximationTolerance: length(1e-7))
        #expect(abs(try evaluate(round).brep.volume(tolerance: .standard) - Double.pi * r * r * L) < 1e-12)

        var hollow = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try hollow.pipe(along: try line(in: &hollow), diameter: length(2 * r), thickness: length(0.001),
                            start: scalar(0.2), end: scalar(0.8), approximationTolerance: length(1e-7))
        #expect(abs(try evaluate(hollow).brep.volume(tolerance: .standard) - Double.pi * (r * r - 0.004 * 0.004) * 0.6 * L) < 1e-12)

        var hexagon = DocumentBuilder(units: .meters, tolerance: .standard)
        _ = try hexagon.pipe(along: try line(in: &hexagon), diameter: length(2 * r), vertexCount: 6,
                             angle: .constant(.angle(15, unit: .degree)), approximationTolerance: length(1e-7))
        #expect(abs(try evaluate(hexagon).brep.volume(tolerance: .standard) - 3 * 3.0.squareRoot() / 2 * r * r * L) < 1e-12)

        let document = try hexagon.build(name: "pipe")
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes == document.designGraph.nodes)
    }

    @Test(.timeLimit(.minutes(2)))
    func aPipeFollowsACurveAndBoresATarget() throws {
        let r = 0.003, allowance = 1e-7
        let controls: [(z: Double, x: Double)] = [(0, 0), (0.02, 0), (0.04, 0.01), (0.05, 0.03)]
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let path = try builder.sketch(on: .zx) { sketch in
            _ = sketch.spline(SketchSpline(controlPoints: controls.map { SketchPoint(x: length($0.z), y: length($0.x)) }))
        }.featureID
        _ = try builder.pipe(along: path, diameter: length(2 * r), approximationTolerance: length(allowance))
        let evaluated = try evaluate(builder)
        let nodes = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
        let weights = [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
        func speed(_ t: Double) -> Double {
            let a = 3 * (1 - t) * (1 - t), b = 6 * (1 - t) * t, c = 3 * t * t
            let dz = a * (controls[1].z - controls[0].z) + b * (controls[2].z - controls[1].z) + c * (controls[3].z - controls[2].z)
            let dx = a * (controls[1].x - controls[0].x) + b * (controls[2].x - controls[1].x) + c * (controls[3].x - controls[2].x)
            return (dz * dz + dx * dx).squareRoot()
        }
        let pathLength = (0..<256).reduce(0.0) { sum, index in
            let lower = Double(index) / 256, half = 0.5 / 256
            return sum + zip(nodes, weights).reduce(0.0) { $0 + $1.1 * speed(lower + half * (1 + $1.0)) } * half
        }
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - Double.pi * r * r * pathLength)
            <= 2 * Double.pi * r * pathLength * allowance + 1e-12)

        // A straight pipe through a 20 mm box standing across it bores a round hole.
        var bored = DocumentBuilder(units: .meters, tolerance: .standard)
        let box = try bored.box(
            placement: PrimitivePlacement(origin: Point3D(x: -0.01, y: -0.01, z: 0.01), axis: .unitZ, referenceDirection: .unitX),
            width: length(0.02), depth: length(0.02), height: length(0.02)
        )
        _ = try bored.pipe(along: try line(in: &bored), diameter: length(0.01), booleanOperation: .difference,
                           targets: [box], approximationTolerance: length(1e-7))
        let result = try evaluate(bored)
        #expect(result.brep.bodies.count == 1)
        #expect(abs(try result.brep.volume(tolerance: .standard) - (0.02 * 0.02 * 0.02 - Double.pi * 0.005 * 0.005 * 0.02)) < 1e-12)
    }
}
