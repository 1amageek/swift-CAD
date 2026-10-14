import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections

@main struct BoundedSphereConeSSIKernelAcceptance {
    static func main() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 2, y: 0, z: -4), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        let result = try DefaultSurfaceSurfaceIntersector().intersections(first: sphere, second: cone, tolerance: .standard)
        guard result.count == 1 else { fatalError("The complete original common curve is required.") }
        let first = Face(surfaceID: SurfaceID(), loops: []), second = Face(surfaceID: SurfaceID(), loops: [])
        let model = BRepModel(faces: [first.id: first, second.id: second])
        let pair = BooleanFacePairCandidate(targetFaceID: first.id, toolFaceID: second.id)
        let graph = BooleanIntersectionGraph(facePairs: [pair], boundaryContacts: [],
            faceIntersections: [.init(facePair: pair, geometry: result[0])])
        do {
            try graph.validate(in: model, tolerance: .standard)
            fatalError("Unconverted material clipping cannot discard the all-UV source owner.")
        } catch let error as KernelError {
            guard error.code == .unsupportedCapability else { throw error }
        }
        print("PASS actual Boolean graph preserves the symbolic material-refinement refusal")
    }
}
