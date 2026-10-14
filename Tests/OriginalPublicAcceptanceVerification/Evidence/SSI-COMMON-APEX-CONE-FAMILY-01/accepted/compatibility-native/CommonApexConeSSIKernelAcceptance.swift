import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections

@main struct CommonApexConeSSIKernelAcceptance {
    static func main() throws {
        let sphere=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
        let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitY,halfAngle:Double(bitPattern:0x3fd6f61941e4def1)))
        let result = try DefaultSurfaceSurfaceIntersector().intersections(first: sphere, second: cone, tolerance: .standard)
        guard result.count == 1 else { fatalError("The complete original common curve is required.") }
        let first = Face(surfaceID: SurfaceID(), loops: []), second = Face(surfaceID: SurfaceID(), loops: [])
        let model = BRepModel(faces: [first.id: first, second.id: second])
        let pair = BooleanFacePairCandidate(targetFaceID: first.id, toolFaceID: second.id)
        for value in result {
        let graph = BooleanIntersectionGraph(facePairs: [pair], boundaryContacts: [],
            faceIntersections: [.init(facePair: pair, geometry: value)])
        do {
            try graph.validate(in: model, tolerance: .standard)
            fatalError("Unconverted material clipping cannot discard the all-UV source owner.")
        } catch let error as KernelError {
            guard error.code == .unsupportedCapability else { throw error }
        }
        }
        print("PASS actual Boolean graph preserves the symbolic material-refinement refusal")
    }
}
