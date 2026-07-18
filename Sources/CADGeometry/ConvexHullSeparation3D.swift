import CADCore

enum ConvexHullSeparation3D {
    static func provesSeparated(
        first: [Point3D],
        second: [Point3D],
        tolerance: Double,
        maximumIterations: Int = 64
    ) -> Bool {
        guard first.isEmpty == false,
              second.isEmpty == false,
              tolerance.isFinite,
              tolerance >= 0.0,
              maximumIterations > 0 else {
            return false
        }
        let differences = first.flatMap { firstPoint in
            second.map { firstPoint - $0 }
        }
        guard var closest = differences.min(by: { $0.length < $1.length }) else {
            return false
        }
        for _ in 0..<maximumIterations {
            let length = closest.length
            if length <= tolerance {
                return false
            }
            guard let support = differences.min(by: {
                closest.dot($0) < closest.dot($1)
            }) else {
                return false
            }
            let separatingDistance = closest.dot(support) / length
            if separatingDistance > tolerance {
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
}
