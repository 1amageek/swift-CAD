import CADCore
import CADGeometry

struct FaceTrimBoundaryProjection: Sendable, Hashable {
    let parameter: SurfaceParameter
    let point: Point3D
    let residual: Double
    let iterations: Int
}
