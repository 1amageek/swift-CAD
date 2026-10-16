/// Nominates two original chart boundaries; admission still proves their exact source identity.
public struct OriginalSurfaceSharedBoundary: Sendable {
  public let first: SurfaceParameterBoundary
  public let second: SurfaceParameterBoundary
  public init(first: SurfaceParameterBoundary, second: SurfaceParameterBoundary) {
    self.first = first
    self.second = second
  }
}
