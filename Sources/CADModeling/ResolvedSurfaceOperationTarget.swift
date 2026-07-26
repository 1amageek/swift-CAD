import CADCore
import CADGeometry
import CADTopology

package struct ResolvedSurfaceOperationTarget: Sendable {
    package let bodyID: BodyID
    package let shellID: ShellID
    package let faceID: FaceID
    package let body: Body
    package let shell: Shell
    package let face: Face
    package let surface: Surface3D
}
