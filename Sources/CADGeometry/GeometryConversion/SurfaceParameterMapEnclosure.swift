/// Original UV image, Jacobian and Hessian bounds over one complete consumer box.
public struct SurfaceParameterMapEnclosure: Sendable {
    public let u: SurfaceParameterMapCoordinateEnclosure
    public let v: SurfaceParameterMapCoordinateEnclosure

    public init(u: SurfaceParameterMapCoordinateEnclosure,
        v: SurfaceParameterMapCoordinateEnclosure) {
        self.u = u
        self.v = v
    }
}
