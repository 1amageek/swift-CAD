import CADCore
import CADGeometry
import CADIR

/// An immutable original support tied to the queried stable face source.
public struct ResolvedOriginalSurfaceGeometry: Sendable, Hashable {
    public let reference: SurfaceReference
    public let faceID: FaceID
    public let surfaceID: SurfaceID
    public let surface: Surface3D

    package init(reference: SurfaceReference, faceID: FaceID, surfaceID: SurfaceID, surface: Surface3D) {
        self.reference = reference
        self.faceID = faceID
        self.surfaceID = surfaceID
        self.surface = surface
    }
}
