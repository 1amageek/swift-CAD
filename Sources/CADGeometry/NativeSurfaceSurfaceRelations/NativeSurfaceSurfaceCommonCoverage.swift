import CADCore

/// Genuine whole original-chart coverage consumed below public Geometry adapters.
package struct NativeSurfaceSurfaceCommonCoverage: Sendable {
    package let charts: [NativeSurfaceSurfaceSourceChart]
    package let nativeDomains: [OriginalRationalParameterDomain]
    package let requestedDomains: [OriginalRationalParameterDomain]
    package let effectiveDomains: [OriginalRationalParameterDomain]?
    package let laws: [ExactIntersectionPolynomial]
    package let predicate: OriginalPolynomialPredicate
    package let partition: OriginalRationalIntersectionCells
    package let incidence: OriginalRationalIntersectionIncidence
    package let connected: OriginalRationalParameterComponents
    package let chartOwners: [Int]
    package let ranks: [Int]
    /// Nonnegative physical ordinal, -1 exact fixed sign, or -2 bounded corner zero evidence.
    package let originalLawOrdinals: [Int]
    package let originalLawUnits: [ExactRationalCoefficient]
    package let originalLawFixedSigns: [OriginalPolynomialPredicate.Sign]
    package let finiteCoordinateWitnesses: [Int]
    package let necessaryCoordinateEquations: [ExactIntersectionPolynomial]
    package let necessaryIdeal: ExactIntersectionIdeal
    package let commonNecessaryEquationStart: Int
    package let necessaryChartWitnesses: [[Int]]
    package let sourceBindings: [Binding]
    package let originalLaws: [ExactIntersectionPolynomial]
    package let maximumComponentCount: Int
}
