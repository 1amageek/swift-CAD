import CADCore

enum ConvexHullSeparation3D {
    static func provesSeparated(first: [Point3D], second: [Point3D], tolerance: Double,
        maximumIterations: Int = 64) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try provesSeparated(first: first, second: second, tolerance: tolerance,
            maximumIterations: maximumIterations, using: &execution)
    }

    static func provesSeparated<A: ExactScalarAdmission & ~Copyable>(
        first: [Point3D],
        second: [Point3D],
        tolerance: Double,
        maximumIterations: Int = 64, using execution: inout A
    ) throws -> Bool {
        try execution.checkpoint()
        guard first.isEmpty == false,
              second.isEmpty == false,
              tolerance.isFinite,
              tolerance >= 0.0,
              maximumIterations > 0 else {
            return false
        }
        let count = first.count.multipliedReportingOverflow(by: second.count)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        try OriginalCoefficientAllocation.reserve(count: count.partialValue, of: Vector3D.self, using: &execution)
        var differences: [Vector3D] = []
        differences.reserveCapacity(count.partialValue)
        for firstPoint in first { for secondPoint in second {
            try execution.consumeWork(1)
            differences.append(firstPoint - secondPoint)
        } }
        guard var closest = try differences.min(by: { try execution.consumeWork(1); return $0.length < $1.length }) else {
            return false
        }
        for _ in 0..<maximumIterations {
            try execution.consumeWork(1)
            let length = closest.length
            if length <= tolerance {
                return false
            }
            guard let support = try differences.min(by: {
                try execution.consumeWork(1)
                return closest.dot($0) < closest.dot($1)
            }) else {
                return false
            }
            if try provesSeparatingPlane(
                normal: closest,
                points: differences,
                tolerance: tolerance, using: &execution
            ) {
                return true
            }
            let direction = support - closest
            let denominator = direction.dot(direction)
            guard denominator > Double.ulpOfOne else {
                return false
            }
            let fraction = min(max(-closest.dot(direction) / denominator, 0.0), 1.0)
            let updated = closest + direction * fraction
            if (updated - closest).length <= Double.ulpOfOne * max(1.0, length) {
                return false
            }
            closest = updated
        }
        return false
    }

    static func provesSeparatingPlane(normal: Vector3D, points: [Vector3D], tolerance: Double) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try provesSeparatingPlane(normal: normal, points: points, tolerance: tolerance, using: &execution)
    }

    static func provesSeparatingPlane<A: ExactScalarAdmission & ~Copyable>(
        normal: Vector3D,
        points: [Vector3D],
        tolerance: Double, using execution: inout A
    ) throws -> Bool {
        try execution.checkpoint()
        let lengthUpperBound = normal.length.nextUp
        guard lengthUpperBound.isFinite,
              lengthUpperBound > 0.0 else {
            return false
        }
        let thresholdInterval = OutwardScalarInterval(tolerance * lengthUpperBound)
        return try points.allSatisfy { point in
            try execution.consumeWork(1)
            let dotInterval = OutwardScalarInterval(normal.x * point.x)
                + OutwardScalarInterval(normal.y * point.y)
                + OutwardScalarInterval(normal.z * point.z)
            if dotInterval.lower > thresholdInterval.upper { return true }
            if dotInterval.upper <= thresholdInterval.lower { return false }
            let threshold = try FloatingPointExpansion.product([tolerance], [lengthUpperBound], using: &execution)
            let x = try FloatingPointExpansion.product([normal.x], [point.x], using: &execution)
            let y = try FloatingPointExpansion.product([normal.y], [point.y], using: &execution)
            let z = try FloatingPointExpansion.product([normal.z], [point.z], using: &execution)
            let xy = try FloatingPointExpansion.sum(x, y, using: &execution)
            let dotProduct = try FloatingPointExpansion.sum(xy, z, using: &execution)
            let difference = try FloatingPointExpansion.subtract(dotProduct, threshold, using: &execution)
            return try FloatingPointExpansion.sign(difference, using: &execution) == .positive
        }
    }
}
