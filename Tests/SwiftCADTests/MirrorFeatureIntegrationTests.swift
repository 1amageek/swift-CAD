import Foundation
import Testing
@testable import SwiftCAD

@Suite("Mirror feature integration")
struct MirrorFeatureIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func mirrorDuplicatesBoxAcrossSeparatedPlaneAndRoundTripsNativePackage() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let extrudeID = try appendBox(to: &builder)
        let mirrorID = try builder.mirror(
            extrudeID,
            planeOrigin: Point3D(x: 0.05, y: 0.0, z: 0.0),
            planeNormal: .unitX
        )
        let document = try builder.build(name: "Mirror parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 2)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 2.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .mirror = loaded.designGraph.nodes[mirrorID]?.operation else {
            Issue.record("Native package persistence must preserve the shared mirror operation.")
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
