import CADCore
import CADGeometry
@main struct SphereConeParentSSIObservation {
    static func main() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 2, y: 0, z: -4), axis: .unitZ,
            halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: sphere, second: cone,
            options: .init(), tolerance: .standard)
        print("SSI component count", result.intersections.count)
        print("source-bound issued relation", result.originalIssuedGeometricRelation != nil)
        print("exact geometric relation", result.originalExactGeometricRelation != nil)
        print("coaxial family relation", result.originalCoaxialSurfaceRelation != nil)
        print("numerical representatives", result.representation == .numericalRepresentatives)
    }
}
