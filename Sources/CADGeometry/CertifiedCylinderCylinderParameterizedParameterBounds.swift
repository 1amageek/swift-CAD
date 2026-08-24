import CADCore

/// Geometry-owned bounds for the exact parameter trace on the cylinder that
/// defines a certified cylinder-cylinder component. Topology consumers use
/// these values without reconstructing parameter derivatives from spatial
/// metric bounds.
package struct CertifiedCylinderCylinderParameterizedParameterBounds: Sendable {
    package let uLift: ScalarInterval
    package let vLift: ScalarInterval
    package let totalVariationU: Double
    package let totalVariationV: Double
    package let firstDerivativeMagnitude: Double
    package let secondDerivativeMagnitude: Double
    package let thirdDerivativeMagnitude: Double
}
