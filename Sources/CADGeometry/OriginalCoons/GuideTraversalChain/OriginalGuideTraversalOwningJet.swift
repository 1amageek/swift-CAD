import CADCore

/// One declared guide station interval and its original one-sided derivatives.
package struct OriginalGuideTraversalOwningJet: Sendable {
  package let traversalIndex: Int
  package let exactLower: ExactRationalCoefficient
  package let exactUpper: ExactRationalCoefficient
  package let parameters: ScalarInterval
  package let jet: IntervalVectorDerivativeJet
}
