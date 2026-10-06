/// A finite original-chart enclosure requires caller-owned boundary refinement.
/// Consumers subdivide the boundary fraction under their finite work budget.
package enum SurfaceAreaEnclosureRefinementRequired: Error, Sendable {
    case parameterDomain
    case implicitLocalization
}
