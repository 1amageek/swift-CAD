/// Immutable original homogeneous winding law on one selected native owner.
package struct OriginalPlanarWindingNativeOwner: Sendable {
  package let original: OriginalRationalCurvePolynomial
  package let lower: ExactRationalCoefficient
  package let upper: ExactRationalCoefficient
  package let reversed: Bool
}
