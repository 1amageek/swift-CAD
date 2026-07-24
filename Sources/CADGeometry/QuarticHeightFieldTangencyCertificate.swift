import CADCore
import Foundation

struct QuarticHeightFieldTangencyCertificate: Sendable {
    typealias Witness = ExactPlaneHeightFieldContext.Witness

    let witness: Witness

    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> QuarticHeightFieldTangencyCertificate? {
        if let context = ExactPlaneHeightFieldContext(surface: first),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: second,
               planeIsFirst: true,
               tolerance: tolerance
           ) {
            return certificate
        }
        if let context = ExactPlaneHeightFieldContext(surface: second),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: first,
               planeIsFirst: false,
               tolerance: tolerance
           ) {
            return certificate
        }
        return nil
    }

    private static func heightCertificate(
        context: ExactPlaneHeightFieldContext,
        heightSurface: BSplineSurface3D,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> QuarticHeightFieldTangencyCertificate? {
        guard ExactPlaneHeightFieldContext.isSingleSpan(heightSurface),
              ExactPlaneHeightFieldContext.hasConstantWeights(heightSurface),
              heightSurface.uDegree == 4,
              heightSurface.vDegree == 4,
              let heightControls = context.exactHeightControls(for: heightSurface),
              let isolatedParameter = isolatedQuarticPowerSumRoot(
                  bernsteinControlExpansions: heightControls
              ) else {
            return nil
        }
        return QuarticHeightFieldTangencyCertificate(
            witness: try context.verifiedWitness(
                on: heightSurface,
                normalized: isolatedParameter,
                planeIsFirst: planeIsFirst,
                certificateName: "quartic tangency",
                tolerance: tolerance
            )
        )
    }

    private static func isolatedQuarticPowerSumRoot(
        bernsteinControlExpansions: [[[Double]]]
    ) -> Point2D? {
        guard bernsteinControlExpansions.count == 5,
              bernsteinControlExpansions.allSatisfy({ $0.count == 5 }) else {
            return nil
        }
        let power = powerCoefficients(
            bernsteinControlExpansions: bernsteinControlExpansions
        )
        let uLeading = power[0][4]
        let vLeading = power[4][0]
        let uSign = ExactExpansionArithmetic.sign(uLeading)
        let vSign = ExactExpansionArithmetic.sign(vLeading)
        guard uSign != .zero,
              uSign == vSign else {
            return nil
        }
        let uLeadingEstimate = ExactExpansionArithmetic.estimate(uLeading)
        let vLeadingEstimate = ExactExpansionArithmetic.estimate(vLeading)
        let uCubicEstimate = ExactExpansionArithmetic.estimate(power[0][3])
        let vCubicEstimate = ExactExpansionArithmetic.estimate(power[3][0])
        guard uLeadingEstimate.isFinite,
              vLeadingEstimate.isFinite,
              uLeadingEstimate != 0.0,
              vLeadingEstimate != 0.0 else {
            return nil
        }
        let uRoot = -uCubicEstimate / (4.0 * uLeadingEstimate)
        let vRoot = -vCubicEstimate / (4.0 * vLeadingEstimate)
        guard uRoot.isFinite,
              vRoot.isFinite,
              uRoot >= 0.0,
              uRoot <= 1.0,
              vRoot >= 0.0,
              vRoot <= 1.0 else {
            return nil
        }

        for vPower in 0...4 {
            for uPower in 0...4 {
                var expected: [Double] = [0.0]
                if vPower == 0 {
                    expected = ExactExpansionArithmetic.add(
                        expected,
                        quarticPowerCoefficient(
                            leading: uLeading,
                            root: uRoot,
                            power: uPower
                        )
                    )
                }
                if uPower == 0 {
                    expected = ExactExpansionArithmetic.add(
                        expected,
                        quarticPowerCoefficient(
                            leading: vLeading,
                            root: vRoot,
                            power: vPower
                        )
                    )
                }
                guard ExactExpansionArithmetic.sign(
                    ExactExpansionArithmetic.subtract(
                    power[vPower][uPower],
                    expected
                    )
                ) == .zero else {
                    return nil
                }
            }
        }
        return Point2D(x: uRoot, y: vRoot)
    }

    private static func powerCoefficients(
        bernsteinControlExpansions: [[[Double]]]
    ) -> [[[Double]]] {
        (0...4).map { vPower in
            (0...4).map { uPower in
                var coefficient: [Double] = [0.0]
                for vIndex in 0...vPower {
                    for uIndex in 0...uPower {
                        let sign = (vPower - vIndex + uPower - uIndex).isMultiple(of: 2)
                            ? 1.0
                            : -1.0
                        let scale = sign
                            * binomial(4, vPower)
                            * binomial(vPower, vIndex)
                            * binomial(4, uPower)
                            * binomial(uPower, uIndex)
                        coefficient = ExactExpansionArithmetic.add(
                            coefficient,
                            ExactExpansionArithmetic.multiply(
                                bernsteinControlExpansions[vIndex][uIndex],
                                [scale]
                            )
                        )
                    }
                }
                return coefficient
            }
        }
    }

    private static func quarticPowerCoefficient(
        leading: [Double],
        root: Double,
        power: Int
    ) -> [Double] {
        ExactExpansionArithmetic.multiply(
            ExactExpansionArithmetic.multiply(leading, [binomial(4, power)]),
            exactPower(-root, exponent: 4 - power)
        )
    }

    private static func exactPower(_ value: Double, exponent: Int) -> [Double] {
        guard exponent > 0 else { return [1.0] }
        return (0..<exponent).reduce([1.0]) { result, _ in
            ExactExpansionArithmetic.multiply(result, [value])
        }
    }

    private static func binomial(_ degree: Int, _ index: Int) -> Double {
        let reducedIndex = min(index, degree - index)
        guard reducedIndex > 0 else { return 1.0 }
        return (1...reducedIndex).reduce(1.0) { result, step in
            result * Double(degree - reducedIndex + step) / Double(step)
        }
    }

}
