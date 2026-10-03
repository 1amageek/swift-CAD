import Foundation
import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel
@testable import SwiftCAD

/// Plasticity's Loop over open curves: four open curves lofted with Loop make one closed smooth
/// band, open only at the curves' ends.
@Suite("Loft open curve loop")
struct LoftOpenCurveLoopTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }

    @Test(.timeLimit(.minutes(2)), arguments: [LoftSurfaceMode.smooth, .ruled])
    func fourOpenCurvesLoopIntoOneClosedBand(surfaceMode: LoftSurfaceMode) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        // Lines along X, 20 mm long, around the X axis at radius 10 mm, a quarter turn apart.
        let radius = 0.01
        let lines = try (0..<4).map { k -> FeatureID in
            let angle = Double(k) * Double.pi / 2
            let y = radius * cos(angle), z = radius * sin(angle)
            return try builder.sketch(on: .plane(Plane3D(origin: Point3D(x: 0, y: y, z: z), normal: .unitZ))) { sketch in
                _ = sketch.line(from: SketchPoint(x: length(0), y: length(0)), to: SketchPoint(x: length(0.02), y: length(0)))
            }.featureID
        }
        _ = try builder.loft(
            sections: lines.map { LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0))) },
            options: LoftOptions(resultKind: .sheet, closesSectionLoop: true, surfaceMode: surfaceMode)
        )
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "loop"))
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let sheets = evaluated.brep.bodies.values.filter { $0.kind == .sheet }
        #expect(sheets.count == 1)
        // Every edge bounding only one face lies at one of the curves' ends, x = 0 or x = 20 mm:
        // the band closes around through its last curve back to its first.
        var uses: [EdgeID: Int] = [:]
        for loop in evaluated.brep.loops.values {
            for coedge in loop.coedges { uses[coedge.edgeID, default: 0] += 1 }
        }
        let free = uses.filter { $0.value == 1 }.map(\.key)
        #expect(free.isEmpty == false)
        for edgeID in free {
            let edge = try #require(evaluated.brep.edges[edgeID])
            let start = try #require(evaluated.brep.vertices[edge.startVertexID]?.point)
            let end = try #require(evaluated.brep.vertices[edge.endVertexID]?.point)
            #expect(abs(start.x - end.x) < 1e-9 && (abs(start.x) < 1e-9 || abs(start.x - 0.02) < 1e-9), "free edge \(start) → \(end)")
        }
    }
}
