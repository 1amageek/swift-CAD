import CADCore
import Foundation

struct StableHeightQuadraticRootSolver {
    func roots(
        coefficients: (
            leading: Double,
            linear: Double,
            constant: Double
        ),
        characteristicLength: Double,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let a = coefficients.leading
        let b = coefficients.linear
        let c = coefficients.constant
        if a == 0.0 {
            guard b != 0.0 else { return [] }
            return [-c / b]
        }
        let discriminant = b * b - 4.0 * a * c
        let equationScale = abs(a) * characteristicLength
                * characteristicLength
            + abs(b) * characteristicLength
            + abs(c)
        let discriminantTolerance = max(
            Double.ulpOfOne * equationScale * 8_192.0,
            tolerance.distance * max(characteristicLength, 1.0) * 1.0e-6
        )
        guard discriminant >= -discriminantTolerance else {
            return []
        }
        let rootDiscriminant = sqrt(max(discriminant, 0.0))
        if rootDiscriminant <= sqrt(discriminantTolerance) {
            return [-b / (2.0 * a)]
        }
        let signedRoot = b >= 0.0
            ? rootDiscriminant
            : -rootDiscriminant
        let q = -0.5 * (b + signedRoot)
        guard q != 0.0 else {
            return [-b / (2.0 * a)]
        }
        return [q / a, c / q]
    }
}
