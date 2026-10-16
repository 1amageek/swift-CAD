import CADCore

public struct SurfaceParameterBox: Equatable, Hashable, Sendable {
  public let u: ScalarInterval
  public let v: ScalarInterval

  public init(u: ScalarInterval, v: ScalarInterval) {
    self.u = u
    self.v = v
  }


}

#if !hasFeature(Embedded)
extension SurfaceParameterBox: Codable {}
#endif
