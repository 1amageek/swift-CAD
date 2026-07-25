protocol ConeCylinderConePolynomialBuilding: Sendable {
    func polynomial(
        context: ConeCylinderConeIntersectionContext
    ) -> ConeCylinderConePolynomial
}
