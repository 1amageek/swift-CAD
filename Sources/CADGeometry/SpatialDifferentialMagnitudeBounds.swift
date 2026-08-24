struct SpatialDifferentialMagnitudeBounds: Sendable {
    let first: Double
    let second: Double
    /// Bounds the third derivative wherever the curve is C3. For a curve
    /// assembled from C3 pieces with C2 joins, this is also the Lipschitz
    /// bound of the continuous second derivative across those joins.
    let third: Double?

    init(
        first: Double,
        second: Double,
        third: Double? = nil
    ) {
        self.first = first
        self.second = second
        self.third = third
    }

    func scaled(by scale: Double) -> SpatialDifferentialMagnitudeBounds {
        let firstScale = abs(scale).nextUp
        let secondScale = (firstScale * firstScale).nextUp
        let thirdScale = (secondScale * firstScale).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: (first * firstScale).nextUp,
            second: (second * secondScale).nextUp,
            third: third.map { ($0 * thirdScale).nextUp }
        )
    }
}
