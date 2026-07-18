import Testing

@Suite("General Cylinder Boolean Intersection Graph")
struct GeneralCylinderBooleanIntersectionGraphTests {
    @Test(.timeLimit(.minutes(1)))
    func unequalCylinderSheetsReachGraphWithDualPcurves() throws {
        try BooleanIntersectionGraphTests()
            .verifyUnequalCylinderSheetsReachBooleanIntersectionGraphWithDualPcurves()
    }
}
