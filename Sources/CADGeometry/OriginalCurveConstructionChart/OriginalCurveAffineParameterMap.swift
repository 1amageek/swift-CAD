import CADCore

/// Exact original source parameter as gain times normalized parameter plus offset.
package struct OriginalCurveAffineParameterMap: Sendable {
  package let gain: ExactRationalCoefficient
  package let offset: ExactRationalCoefficient
}
