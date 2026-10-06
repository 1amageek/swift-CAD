/// Exact original ideal classification, distinct from numerical or resource failure.
package enum ExactBivariateSystemClassification: Error, Sendable {
    /// The original ideal has positive complex dimension. Real component coverage
    /// remains a separate contract; neither real existence nor emptiness follows.
    case positiveDimensionalOriginalIdeal(equations: [ExactBivariatePolynomial],
                                         reducedBasis: [ExactBivariatePolynomial])
}
