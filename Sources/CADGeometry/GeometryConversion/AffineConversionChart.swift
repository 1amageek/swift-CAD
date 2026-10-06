import CADCore

/// A finite affine parameter law with outward image and derivative arithmetic.
struct AffineConversionChart: Sendable {
    let scale: Double
    let offset: Double

    init(scale: Double, offset: Double) throws {
        guard scale.isFinite, scale != 0, offset.isFinite else {
            throw GeometryConversionError.invalidInput("An affine chart requires a finite nonzero scale and finite offset.")
        }
        self.scale = scale
        self.offset = offset
    }

    func parameter(_ value: Double) throws -> Double {
        try Task.checkCancellation()
        guard value.isFinite else {
            throw GeometryConversionError.invalidInput("An affine chart requires a finite parameter.")
        }
        let result = offset.addingProduct(scale, value)
        guard result.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Affine parameter evaluation overflowed.")
        }
        return result
    }

    func image(_ interval: ScalarInterval) throws -> ScalarInterval {
        try Task.checkCancellation()
        if scale == 1, offset == 0 { return interval }
        let first = endpoint(interval.lower), second = endpoint(interval.upper)
        return try finite(.init(lower: min(first.lower, second.lower), upper: max(first.upper, second.upper)))
    }

    static func multiply(_ coordinates: CoordinateEnclosure3D,
                         by factor: OutwardScalarInterval) throws -> CoordinateEnclosure3D {
        func coordinate(_ value: ScalarInterval) throws -> ScalarInterval {
            try finite(OutwardScalarInterval(lower: value.lower, upper: value.upper) * factor)
        }
        return try .init(x: coordinate(coordinates.x), y: coordinate(coordinates.y), z: coordinate(coordinates.z))
    }

    private static func finite(_ interval: OutwardScalarInterval) throws -> ScalarInterval {
        guard interval.lower.isFinite, interval.upper.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Affine chart interval arithmetic overflowed.")
        }
        return try ScalarInterval(lower: interval.lower, upper: interval.upper)
    }

    private func finite(_ interval: OutwardScalarInterval) throws -> ScalarInterval {
        try Self.finite(interval)
    }

    private func endpoint(_ parameter: Double) -> OutwardScalarInterval {
        // Power-of-two multiplication is exact when its result is normal. An
        // error-free TwoSum then identifies representable endpoint images,
        // avoiding artificial padding beyond an original closed source domain.
        let product = scale * parameter
        let fractionMask: UInt64 = 0x000F_FFFF_FFFF_FFFF
        let exactProduct = scale.bitPattern & fractionMask == 0
            && (product.isNormal || parameter == 0 || abs(scale) == 1)
        let sum = product + offset
        if exactProduct, sum.isFinite {
            let virtualOffset = sum - product
            let residual = (product - (sum - virtualOffset)) + (offset - virtualOffset)
            if residual == 0 { return .exact(sum) }
        }
        return .exact(parameter) * .exact(scale) + .exact(offset)
    }
}
