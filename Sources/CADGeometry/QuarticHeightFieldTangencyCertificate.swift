import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

struct QuarticHeightFieldTangencyCertificate: Sendable {
    typealias Witness = ExactPlaneHeightFieldContext.Witness

    let witness: Witness

    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> QuarticHeightFieldTangencyCertificate? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certified(first: first, second: second, tolerance: tolerance, using: &execution)
    }


    static func certified(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> QuarticHeightFieldTangencyCertificate? {
        try execution.consumeWork(1)
        try first.validate(tolerance: tolerance, using: &execution)
        try second.validate(tolerance: tolerance, using: &execution)

        if let context = try ExactPlaneHeightFieldContext(surface: first, using: &execution),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: second,
               planeIsFirst: true,
               tolerance: tolerance
           , using: &execution) {
            return certificate
        }
        if let context = try ExactPlaneHeightFieldContext(surface: second, using: &execution),
           let certificate = try heightCertificate(
               context: context,
               heightSurface: first,
               planeIsFirst: false,
               tolerance: tolerance
           , using: &execution) {
            return certificate
        }
        return nil
    }



    private static func heightCertificate(
        context: ExactPlaneHeightFieldContext,
        heightSurface: BSplineSurface3D,
        planeIsFirst: Bool,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> QuarticHeightFieldTangencyCertificate? {
        try execution.consumeWork(1)

        guard try ExactPlaneHeightFieldContext.isSingleSpan(heightSurface, using: &execution),
              try ExactPlaneHeightFieldContext.hasConstantWeights(heightSurface, using: &execution),
              heightSurface.uDegree == 4,
              heightSurface.vDegree == 4,
              let heightControls = try context.exactHeightControls(for: heightSurface, using: &execution),
              let isolatedParameter = try isolatedQuarticPowerSumRoot(
                  bernsteinControlExpansions: heightControls
              , using: &execution) else {
            return nil
        }
        return QuarticHeightFieldTangencyCertificate(
            witness: try context.verifiedWitness(
                on: heightSurface,
                normalized: isolatedParameter,
                planeIsFirst: planeIsFirst,
                certificateName: "quartic tangency",
                tolerance: tolerance
            , using: &execution)
        )
    }



    private static func isolatedQuarticPowerSumRoot(
        bernsteinControlExpansions: [[[Double]]]
    , using execution: inout OriginalQueryExecution) throws -> Point2D? {
        try execution.consumeWork(1)

        guard bernsteinControlExpansions.count == 5,
              bernsteinControlExpansions.allSatisfy({ $0.count == 5 }) else {
            return nil
        }
        let power = try powerCoefficients(
            bernsteinControlExpansions: bernsteinControlExpansions
        , using: &execution)
        let uLeading = power[0][4]
        let vLeading = power[4][0]
        let uSign = try ExactExpansionArithmetic.sign(uLeading, using: &execution)
        let vSign = try ExactExpansionArithmetic.sign(vLeading, using: &execution)
        guard uSign != .zero,
              uSign == vSign else {
            return nil
        }
        let uLeadingEstimate = try ExactExpansionArithmetic.estimate(uLeading, using: &execution)
        let vLeadingEstimate = try ExactExpansionArithmetic.estimate(vLeading, using: &execution)
        let uCubicEstimate = try ExactExpansionArithmetic.estimate(power[0][3], using: &execution)
        let vCubicEstimate = try ExactExpansionArithmetic.estimate(power[3][0], using: &execution)
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
                    try execution.consumeWork(1)
            for uPower in 0...4 {
                    try execution.consumeWork(1)
                var expected = try OriginalCoefficientAllocation.singleton(0.0, using: &execution)
                if vPower == 0 {
                    expected = try ExactExpansionArithmetic.add(
                        expected,
                        try quarticPowerCoefficient(
                            leading: uLeading,
                            root: uRoot,
                            power: uPower
                        , using: &execution)
                    , using: &execution)
                }
                if uPower == 0 {
                    expected = try ExactExpansionArithmetic.add(
                        expected,
                        try quarticPowerCoefficient(
                            leading: vLeading,
                            root: vRoot,
                            power: vPower
                        , using: &execution)
                    , using: &execution)
                }
                guard try ExactExpansionArithmetic.sign(
                    try ExactExpansionArithmetic.subtract(
                    power[vPower][uPower],
                    expected
                    , using: &execution)
                , using: &execution) == .zero else {
                    return nil
                }
            }
        }
        return Point2D(x: uRoot, y: vRoot)
    }



    private static func powerCoefficients(
        bernsteinControlExpansions: [[[Double]]]
    , using execution: inout OriginalQueryExecution) throws -> [[[Double]]] {
        try execution.consumeWork(1)

        return try CertifiedAnalyticCurveEvaluation.map(0...4, using: &execution) { vPower, execution in
            try CertifiedAnalyticCurveEvaluation.map(0...4, using: &execution) { uPower, execution in
                var coefficient = try OriginalCoefficientAllocation.singleton(0.0, using: &execution)
                for vIndex in 0...vPower {
                    try execution.consumeWork(1)
                    for uIndex in 0...uPower {
                    try execution.consumeWork(1)
                        let sign = (vPower - vIndex + uPower - uIndex).isMultiple(of: 2)
                            ? 1.0
                            : -1.0
                        let scale = sign
                            * binomial(4, vPower)
                            * binomial(vPower, vIndex)
                            * binomial(4, uPower)
                            * binomial(uPower, uIndex)
                        coefficient = try ExactExpansionArithmetic.add(
                            coefficient,
                            try ExactExpansionArithmetic.multiply(
                                bernsteinControlExpansions[vIndex][uIndex],
                                OriginalCoefficientAllocation.singleton(scale, using: &execution)
                            , using: &execution)
                        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)

        return try ExactExpansionArithmetic.multiply(
            try ExactExpansionArithmetic.multiply(leading, OriginalCoefficientAllocation.singleton(binomial(4, power), using: &execution), using: &execution),
            try exactPower(-root, exponent: 4 - power, using: &execution)
        , using: &execution)
    }



    private static func exactPower(_ value: Double, exponent: Int, using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)

        guard exponent > 0 else { return try OriginalCoefficientAllocation.singleton(1.0, using: &execution) }
        var result = try OriginalCoefficientAllocation.singleton(1.0, using: &execution)
        for _ in 0..<exponent {
            try execution.consumeWork(1)
            result = try ExactExpansionArithmetic.multiply(result,
                OriginalCoefficientAllocation.singleton(value, using: &execution), using: &execution)
        }
        return result
    }

    private static func binomial(_ degree: Int, _ index: Int) -> Double {
        let reducedIndex = min(index, degree - index)
        guard reducedIndex > 0 else { return 1.0 }
        return (1...reducedIndex).reduce(1.0) { result, step in
            result * Double(degree - reducedIndex + step) / Double(step)
        }
    }

}
