import CADCore

/// Exact side of a plane retaining the original point, origin and normal coefficients.
package struct OriginalPointPlaneSide: Sendable {
    package init() {}

    package func sign(point: Point3D, origin: Point3D, normal: Vector3D,
        consumeWork: () throws -> Void) throws -> RobustSign {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        try point.validate(); try origin.validate(); try normal.validate()
        guard normal.x != 0 || normal.y != 0 || normal.z != 0 else {
            throw GeometryConversionError.invalidInput("Exact plane side requires a nonzero original normal.")
        }
        var result: [Double] = []
        for (value, base, coefficient) in [(point.x, origin.x, normal.x),
            (point.y, origin.y, normal.y), (point.z, origin.z, normal.z)] {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
            result = FloatingPointExpansion.sum(result, FloatingPointExpansion.product(
                FloatingPointExpansion.difference(value, base), [coefficient]))
        }
        let side = FloatingPointExpansion.sign(result)
        guard side != .indeterminate else {
            throw GeometryConversionError.resourceLimitExceeded("Exact original plane side expansion is indeterminate.")
        }
        return side
    }
}
