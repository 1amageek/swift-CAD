/// The derivative orders retained by an original supporting-plane constraint.
public enum OriginalPlaneDerivativeOrder: Int, Hashable, Sendable {
    case tangent = 1
    case curvature = 2
}
