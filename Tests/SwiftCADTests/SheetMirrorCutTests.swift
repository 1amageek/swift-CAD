import Testing
import SwiftCAD

@Suite struct SheetMirrorCutTests {
    @Test(.timeLimit(.minutes(1)), arguments: [MirrorFeature.Output.kept, .reflection, .combined])
    func cutsCurvedSheetAndPublishesExactSheet(_ output: MirrorFeature.Output) throws {
        let patch = BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: [0.0, 0.01, 0.02].map { y in [
                Point3D(x: -0.01, y: y, z: 0), Point3D(x: 0.005, y: y, z: 0.01),
                Point3D(x: 0.02, y: y, z: 0)] })
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let source = try builder.bSplineSurface(patch)
        let mirror = try builder.mirror(source, planeOrigin: .origin, planeNormal: .unitX,
            output: output, cutsAtPlane: true)
        let result = try CADPipeline(tolerance: .standard).evaluate(builder.build(name: "Cut sheet"))
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        let xs = result.brep.vertices.values.map(\.point.x)
        #expect(abs((xs.min() ?? .nan) - (output == .reflection ? 0 : -0.01)) < 1e-8)
        #expect(abs((xs.max() ?? .nan) - (output == .kept ? 0 : 0.01)) < 1e-8)
        #expect(result.brep.faces.count == (output == .combined ? 2 : 1))
        let lineage = result.lineage.values.filter { $0.output.featureID == mirror }
        #expect(!lineage.isEmpty)
        #expect(lineage.allSatisfy {
            $0.parents.allSatisfy { $0.featureID == source }
        })
    }
}
