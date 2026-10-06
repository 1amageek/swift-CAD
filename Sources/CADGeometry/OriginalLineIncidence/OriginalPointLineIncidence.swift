import CADCore

/// Exact incidence using original line coefficients, without constructing an axis point.
package struct OriginalPointLineIncidence: Sendable {
    package init() {}

    package func contains(point: Point3D, origin: Point3D, direction: Vector3D,
        consumeWork: () throws -> Void) throws -> Bool {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        try point.validate(); try origin.validate(); try direction.validate()
        guard direction.x != 0 || direction.y != 0 || direction.z != 0 else {
            throw GeometryConversionError.invalidInput("Exact line incidence requires an original nonzero direction.")
        }
        let offsets = [FloatingPointExpansion.difference(point.x, origin.x),
            FloatingPointExpansion.difference(point.y, origin.y),
            FloatingPointExpansion.difference(point.z, origin.z)]
        let axis = [direction.x, direction.y, direction.z]
        for index in 0..<3 {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
            let first = (index + 1) % 3, second = (index + 2) % 3
            let component = FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(offsets[first], [axis[second]]),
                FloatingPointExpansion.product(offsets[second], [axis[first]]))
            switch FloatingPointExpansion.sign(component) {
            case .zero: continue
            case .negative, .positive: return false
            case .indeterminate:
                throw GeometryConversionError.resourceLimitExceeded("Exact original line incidence expansion is indeterminate.")
            }
        }
        return true
    }
}
