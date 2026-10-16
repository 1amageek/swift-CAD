import CADCore

/// Original pair residuals and positive-weight denominator in one retained field.
struct OriginalAtlasCurveCurveFieldEquationSet: Sendable {
  let equations: [OriginalSingularFieldPlanePolynomial]
  let denominator: OriginalSingularFieldPlanePolynomial
}
