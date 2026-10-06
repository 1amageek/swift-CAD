import CADCore

/// Immutable original law authority retained once for one selected atlas chart.
struct OriginalAtlasCurveHomogeneousPolynomial: Sendable {
    let source: Curve3D
    let nativeIndex: Int
    let nativeDomain: ScalarInterval
    let originalPeriodicCycle: Double?
    let alongU: Bool
    let values: [ExactBivariatePolynomial]
}
