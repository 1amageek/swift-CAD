protocol ConeCylinderSpherePolynomialBuilding: Sendable {
    func polynomial(
        context: ConeCylinderSphereIntersectionContext
    ) -> ConeCylinderSpherePolynomial
}
