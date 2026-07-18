import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Shell builder")
struct ShellBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedShellCommand() throws {
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
        let removedFace = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .startFace)
        )
        let shellID = try builder.shell(
            target: extrudeID,
            removing: [removedFace],
            thickness: .constant(.length(2.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Shell parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 14)
        guard case .shell = loaded.designGraph.nodes[shellID]?.operation else {
            Issue.record("Native package persistence must preserve the shared shell operation.")
            return
        }
    }
}
