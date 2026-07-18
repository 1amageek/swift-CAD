package struct PlanarSheetParameterBounds: Hashable, Sendable {
    package let lowerU: Double
    package let upperU: Double
    package let lowerV: Double
    package let upperV: Double

    package init(lowerU: Double, upperU: Double, lowerV: Double, upperV: Double) {
        self.lowerU = lowerU
        self.upperU = upperU
        self.lowerV = lowerV
        self.upperV = upperV
    }
}
