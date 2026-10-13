import CADCore
import CADGeometry

/// A retained original endpoint frame acting on the entire section law.
package struct ClosedSweepIntervalFrameAction: Sendable {
    private let coefficients: [OutwardScalarInterval]

    package init(origin: Point3D, position: [OutwardScalarInterval],
        tangent: [OutwardScalarInterval], first: [OutwardScalarInterval], second: [OutwardScalarInterval],
        originalTangent: Vector3D, originalFirst: Vector3D, originalSecond: Vector3D,
        cosine: OutwardScalarInterval, sine: OutwardScalarInterval, scale: OutwardScalarInterval,
        admission: GeometryConversionAdmission) throws {
        guard position.count == 3, tangent.count == 3, first.count == 3, second.count == 3 else {
            throw GeometryConversionError.invalidInput("A closed section action requires all three original frame coordinates.")
        }
        try admission.chargeStorage(bytes: 12 * MemoryLayout<OutwardScalarInterval>.stride)
        try admission.chargeStorage(bytes: 12 * MemoryLayout<Double>.stride)
        let along = [originalTangent.x, originalTangent.y, originalTangent.z]
        let across = [originalFirst.x, originalFirst.y, originalFirst.z]
        let up = [originalSecond.x, originalSecond.y, originalSecond.z]
        let source = [origin.x, origin.y, origin.z]
        var values: [OutwardScalarInterval] = []
        values.reserveCapacity(12)
        for row in 0..<3 {
            let a = first[row] * cosine + second[row] * sine
            let b = second[row] * cosine - first[row] * sine
            var translation = position[row]
            for column in 0..<3 {
                try admission.chargeWork()
                let entry = scale * (tangent[row] * .exact(along[column])
                    + a * .exact(across[column]) + b * .exact(up[column]))
                values.append(entry)
                translation = translation - entry * .exact(source[column])
            }
            values.append(translation)
        }
        guard values.allSatisfy({ $0.isFinite }) else {
            throw GeometryConversionError.resourceLimitExceeded("The original endpoint frame action has nonfinite bounds.")
        }
        coefficients = values
    }

    package func apply(_ value: CoordinateEnclosure3D, isPosition: Bool,
        admission: GeometryConversionAdmission) throws -> CoordinateEnclosure3D {
        try admission.chargeStorage(bytes: 3 * MemoryLayout<OutwardScalarInterval>.stride
            + 3 * MemoryLayout<ScalarInterval>.stride)
        let source = [OutwardScalarInterval(lower: value.x.lower, upper: value.x.upper),
            .init(lower: value.y.lower, upper: value.y.upper), .init(lower: value.z.lower, upper: value.z.upper)]
        var output: [ScalarInterval] = []
        output.reserveCapacity(3)
        for row in 0..<3 {
            var sum = isPosition ? coefficients[4 * row + 3] : .exact(0)
            for column in 0..<3 {
                try admission.chargeWork()
                sum = sum + coefficients[4 * row + column] * source[column]
            }
            output.append(try ScalarInterval(lower: sum.lower, upper: sum.upper))
        }
        return CoordinateEnclosure3D(x: output[0], y: output[1], z: output[2])
    }
}
