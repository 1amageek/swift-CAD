import Testing
@testable import SwiftCAD

@Suite("Surface trim and extend builder")
struct SurfaceTrimExtendBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackagePreserveSurfaceTrimAndExtend() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let extrudeID = try builder.extrude(profile, distance: .constant(.length(10.0, unit: .millimeter)))
        var removedFaces = [try builder.stableSubshape(generatedBy: extrudeID, selector: .generated(role: .endFace))]
        for index in 0..<4 {
            removedFaces.append(try builder.stableSubshape(
                generatedBy: extrudeID,
                selector: .generated(role: .sideFace, index: index)
            ))
        }
        let sheetID = try builder.faceDelete(target: extrudeID, faces: removedFaces)
        let trimID = try builder.trimSurface(
            target: sheetID,
            uDomain: .closed(-0.035, -0.005),
            vDomain: .closed(0.005, 0.015)
        )
        let extendID = try builder.extendSurface(
            target: trimID,
            distances: SurfaceExtensionDistances(
                lowerU: .constant(.length(5.0, unit: .millimeter)),
                upperU: .constant(.length(5.0, unit: .millimeter)),
                lowerV: .constant(.length(5.0, unit: .millimeter)),
                upperV: .constant(.length(5.0, unit: .millimeter))
            )
        )
        let document = try builder.build(name: "Exact planar surface trim extend")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 1)
        #expect(evaluated.brep.edges.count == 4)
        #expect(evaluated.brep.vertices.count == 4)
        guard case .surfaceTrim = loaded.designGraph.nodes[trimID]?.operation,
              case .surfaceExtend = loaded.designGraph.nodes[extendID]?.operation else {
            Issue.record("Native package must preserve surface trim and extend operations.")
            return
        }
    }
}
