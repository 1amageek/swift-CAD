import CADCore

/// Whole original signed UV flux and optional smooth midpoint remainder authority.
package struct SurfaceParameterFluxIntegrationBounds: Sendable {
    package let value: OutwardScalarInterval
    package let midpoint: OutwardScalarInterval?
    package let secondDerivative: OutwardScalarInterval?
}
