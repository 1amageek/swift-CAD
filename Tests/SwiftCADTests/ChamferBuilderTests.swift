import Testing
@testable import SwiftCAD

@Suite("Chamfer builder")
struct ChamferBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderUsesSharedCommandPathForExactChamfer() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy, named: "Base sketch") { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let extrudeID = try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter)),
            named: "Extrude"
        )
        let selectedEdge = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .edge, index: 0)
        )
        let chamferID = try builder.chamfer(
            target: extrudeID,
            edges: [selectedEdge],
            distance: .constant(.length(2.0, unit: .millimeter)),
            named: "Chamfer"
        )
        let document = try builder.build(name: "Chamfer command parity")

        let evaluated = try CADPipeline(tolerance: .standard).evaluate(document)
        let sink = DataByteSink()
        let pipeline = CADPipeline(tolerance: .standard)
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        #expect(document.designGraph.order.count == 3)
        guard case .chamfer = document.designGraph.nodes[chamferID]?.operation else {
            Issue.record("DocumentBuilder must emit the shared chamfer FeatureOperation.")
            return
        }
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 7)
        guard case .chamfer = loaded.designGraph.nodes[chamferID]?.operation else {
            Issue.record("Native package persistence must preserve the chamfer operation.")
            return
        }
    }
}
