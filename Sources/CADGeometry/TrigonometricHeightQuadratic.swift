struct TrigonometricHeightQuadratic: Sendable {
    let leading: SecondOrderTrigonometricPolynomial
    let halfLinear: SecondOrderTrigonometricPolynomial
    let constant: SecondOrderTrigonometricPolynomial

    func coefficients(at angle: Double) -> (
        leading: Double,
        linear: Double,
        constant: Double
    ) {
        (
            leading.value(at: angle),
            2.0 * halfLinear.value(at: angle),
            constant.value(at: angle)
        )
    }
}
