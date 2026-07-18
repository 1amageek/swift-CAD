import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Face Knife Builder")
struct FaceKnifeBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedFaceKnifeCommand() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let extrudeID = try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
        let face = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .startFace)
        )
        let knifeID = try builder.faceKnife(
            target: extrudeID,
            face: face,
            loop: [
                Point3D(x: -0.010, y: -0.005, z: 0.0),
                Point3D(x: 0.010, y: -0.005, z: 0.0),
                Point3D(x: 0.010, y: 0.005, z: 0.0),
                Point3D(x: -0.010, y: 0.005, z: 0.0),
            ]
        )
        let document = try builder.build(name: "Face Knife parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .faceKnife = loaded.designGraph.nodes[knifeID]?.operation else {
            Issue.record("Native package persistence must preserve the shared Face Knife operation.")
            return
        }
    }
}
