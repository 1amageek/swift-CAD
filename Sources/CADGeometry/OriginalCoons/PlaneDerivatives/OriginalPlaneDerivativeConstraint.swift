/// Original supporting source and its requested generated derivative order.
public struct OriginalPlaneDerivativeConstraint: Hashable, Sendable {
  public let surface: Surface3D
  public let order: OriginalPlaneDerivativeOrder

  public init(surface: Surface3D, order: OriginalPlaneDerivativeOrder) {
    self.surface = surface
    self.order = order
  }
}
