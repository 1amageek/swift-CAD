import Testing
@testable import SwiftCAD

@Suite("Thicken builder")
struct ThickenBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderCommandAndNativePackageShareExactThickenOperation() throws {
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
        var removedFaces = [try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .endFace)
        )]
        for index in 0..<4 {
            removedFaces.append(try builder.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .sideFace, index: index)
            ))
        }
        let sheetID = try builder.faceDelete(
            target: extrudeID,
            faces: removedFaces
        )
        let thickenID = try builder.thicken(
            target: sheetID,
            thickness: .constant(.length(4.0, unit: .millimeter)),
            side: .symmetric
        )
        let document = try builder.build(name: "Thicken parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * 0.004) <= 1.0e-12)
        guard case let .thicken(thicken) = loaded.designGraph.nodes[thickenID]?.operation else {
            Issue.record("Native package persistence must preserve the shared thicken operation.")
            return
        }
        #expect(thicken.side == .symmetric)
    }
}
