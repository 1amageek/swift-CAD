import CADCore

/// Original D0/D1 bounds, without a higher continuity or derivative claim.
package struct OriginalCurveFirstOrderJet: Sendable {
    package let position: IntervalVector3DBounds
    package let firstDerivative: IntervalVector3DBounds

    init(position: IntervalVector3DBounds, firstDerivative: IntervalVector3DBounds) {
        self.position = position
        self.firstDerivative = firstDerivative
    }
}
