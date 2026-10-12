struct CertifiedIntervalSummation {
    static func sum(
        _ values: [SurfaceParameterAreaBounds]
    ) -> SurfaceParameterAreaBounds {
        sum(values, bounds: { $0 })
    }

    static func sum<Value>(
        _ values: [Value],
        bounds: (Value) -> SurfaceParameterAreaBounds
    ) -> SurfaceParameterAreaBounds {
        sum(
            values,
            lowerIndex: 0,
            upperIndex: values.count,
            bounds: bounds
        )
    }

    private static func sum<Value>(
        _ values: [Value],
        lowerIndex: Int,
        upperIndex: Int,
        bounds: (Value) -> SurfaceParameterAreaBounds
    ) -> SurfaceParameterAreaBounds {
        let count = upperIndex - lowerIndex
        guard count > 0 else { return .zero }
        guard count > 1 else { return bounds(values[lowerIndex]) }
        let middleIndex = lowerIndex + count / 2
        return sum(
            values,
            lowerIndex: lowerIndex,
            upperIndex: middleIndex,
            bounds: bounds
        ).adding(sum(
            values,
            lowerIndex: middleIndex,
            upperIndex: upperIndex,
            bounds: bounds
        ))
    }
}
