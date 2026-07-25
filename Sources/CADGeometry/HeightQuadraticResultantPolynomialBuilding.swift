protocol HeightQuadraticResultantPolynomialBuilding: Sendable {
    func polynomial(
        first: TrigonometricHeightQuadratic,
        second: TrigonometricHeightQuadratic
    ) -> HeightQuadraticResultantPolynomial
}
