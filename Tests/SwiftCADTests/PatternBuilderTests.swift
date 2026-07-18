import Foundation
import Testing
@testable import SwiftCAD

@Suite("Pattern builder")
struct PatternBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func radialPatternUsesSharedCommandAndNativePackage() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try appendBox(to: &builder)
        let patternID = try builder.radialPattern(
            target: extrudeID,
            axisOrigin: Point3D(x: -100.0, y: 0.0, z: 0.0),
            axisDirection: .unitZ,
            angularSpacing: .constant(.angle(.pi / 2.0, unit: .radian)),
            count: 4
        )
        let document = try builder.build(name: "Radial pattern parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 4)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 4.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .radialPattern = loaded.designGraph.nodes[patternID]?.operation else {
            Issue.record("Native package persistence must preserve the shared radial pattern operation.")
            return
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func gridPatternUsesSharedCommandAndNativePackage() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try appendBox(to: &builder)
        let patternID = try builder.gridPattern(
            target: extrudeID,
            firstDirection: .unitX,
            firstSpacing: .constant(.length(60.0, unit: .millimeter)),
            firstCount: 2,
            secondDirection: .unitY,
            secondSpacing: .constant(.length(40.0, unit: .millimeter)),
            secondCount: 3
        )
        let document = try builder.build(name: "Grid pattern parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 6)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 6.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .gridPattern = loaded.designGraph.nodes[patternID]?.operation else {
            Issue.record("Native package persistence must preserve the shared grid pattern operation.")
            return
        }
    }

    private func appendBox(to builder: inout DocumentBuilder) throws -> FeatureID {
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        return try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
    }
}
