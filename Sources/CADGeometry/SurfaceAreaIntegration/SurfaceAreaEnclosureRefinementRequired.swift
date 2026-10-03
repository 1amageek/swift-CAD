/// A finite enclosing parameter box has not yet been proved inside the support.
/// Consumers subdivide the boundary fraction under their finite work budget.
package enum SurfaceAreaEnclosureRefinementRequired: Error, Sendable {
    case parameterDomain
}
