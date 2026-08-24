import CADGeometry

struct FaceDirectionalSearchDomain: Sendable, Hashable {
    let curve: ScalarInterval
    let surface: SurfaceParameterBox
}
