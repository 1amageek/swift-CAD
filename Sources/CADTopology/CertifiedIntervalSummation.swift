import CADGeometry

struct CertifiedIntervalSummation {
    static func sum<A: ExactScalarAdmission & ~Copyable>(
        _ values: [SurfaceParameterAreaBounds], using execution: inout A
    ) throws -> SurfaceParameterAreaBounds {
        try sum(values, bounds: { value, execution in value }, using: &execution)
    }

    static func sum<Value, A: ExactScalarAdmission & ~Copyable>(
        _ values: [Value],
        bounds: (Value, inout A) throws -> SurfaceParameterAreaBounds,
        using execution: inout A
    ) throws -> SurfaceParameterAreaBounds {
        try sum(
            values,
            lowerIndex: 0,
            upperIndex: values.count,
            bounds: bounds, using: &execution
        )
    }

    private static func sum<Value, A: ExactScalarAdmission & ~Copyable>(
        _ values: [Value],
        lowerIndex: Int,
        upperIndex: Int,
        bounds: (Value, inout A) throws -> SurfaceParameterAreaBounds,
        using execution: inout A
    ) throws -> SurfaceParameterAreaBounds {
        try execution.checkpoint(); try execution.consumeWork(1)
        let count = upperIndex - lowerIndex
        guard count > 0 else { return .zero }
        guard count > 1 else { return try bounds(values[lowerIndex], &execution) }
        let middleIndex = lowerIndex + count / 2
        return try sum(
            values,
            lowerIndex: lowerIndex,
            upperIndex: middleIndex,
            bounds: bounds, using: &execution
        ).adding(sum(
            values,
            lowerIndex: middleIndex,
            upperIndex: upperIndex,
            bounds: bounds, using: &execution
        ))
    }
}
