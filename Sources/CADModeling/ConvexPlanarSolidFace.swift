import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ConvexPlanarSolidFace: Sendable {
    package let faceID: FaceID
    package let surface: Surface3D
    package let orientation: Orientation
    package let planeOrigin: Point3D
    package let outwardNormal: Vector3D
    package let vertices: [Point3D]

    package init(
        faceID: FaceID,
        surface: Surface3D,
        orientation: Orientation,
        planeOrigin: Point3D,
        outwardNormal: Vector3D,
        vertices: [Point3D]
    ) {
        self.faceID = faceID
        self.surface = surface
        self.orientation = orientation
        self.planeOrigin = planeOrigin
        self.outwardNormal = outwardNormal
        self.vertices = vertices
    }
}
