package struct SurfaceParameterAreaBounds: Sendable, Hashable {
    package let lower: Double
    package let upper: Double

    static let zero = SurfaceParameterAreaBounds(lower: 0.0, upper: 0.0)

    var minimumAbsoluteValue: Double {
        if lower <= 0.0, upper >= 0.0 {
            return 0.0
        }
        return min(abs(lower), abs(upper))
    }

    var width: Double {
        (upper - lower).nextUp
    }

    func adding(
        _ other: SurfaceParameterAreaBounds
    ) -> SurfaceParameterAreaBounds {
        SurfaceParameterAreaBounds(
            lower: (lower + other.lower).nextDown,
            upper: (upper + other.upper).nextUp
        )
    }
}
