import CADCore
import Foundation

struct RationalBezierCurveDerivativeBound: Sendable {
    let first: [Double]
    let second: [Double]

    init(
        coordinates: [[Double]],
        weights: [Double],
        parameterWidth: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard coordinates.isEmpty == false,
              coordinates.allSatisfy({ $0.count == weights.count }),
              weights.count >= 2,
              weights.allSatisfy({ $0.isFinite && $0 > Double.ulpOfOne }),
              parameterWidth.isFinite,
              parameterWidth > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier derivative bounds require a positive finite patch."
            )
        }
        let degree = weights.count - 1
        let minimumWeight = (weights.min() ?? 0.0).nextDown
        guard minimumWeight > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: minimumWeight,
                tolerance: tolerance,
                message: "Rational Bezier derivative bounds require a positive weight enclosure."
            )
        }
        let weightFirst = Self.firstDerivativeControlBound(
            weights,
            degree: degree
        )
        let weightSecond = Self.secondDerivativeControlBound(
            weights,
            degree: degree
        )
        let firstScale = Self.upwardDivide(1.0, parameterWidth)
        let secondScale = Self.upwardProduct(firstScale, firstScale)
        var firstResult: [Double] = []
        var secondResult: [Double] = []
        firstResult.reserveCapacity(coordinates.count)
        secondResult.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            let homogeneous = coordinate.indices.map {
                coordinate[$0] * weights[$0]
            }
            guard homogeneous.allSatisfy(\.isFinite) else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational Bezier derivative bounds exceeded finite homogeneous arithmetic."
                )
            }
            let value = Self.maximumAbsolute(homogeneous)
            let numeratorFirst = Self.firstDerivativeControlBound(
                homogeneous,
                degree: degree
            )
            let numeratorSecond = Self.secondDerivativeControlBound(
                homogeneous,
                degree: degree
            )
            let minimumWeightSquared = (
                minimumWeight * minimumWeight
            ).nextDown
            let minimumWeightCubed = (
                minimumWeightSquared * minimumWeight
            ).nextDown
            guard minimumWeightSquared > 0.0,
                  minimumWeightCubed > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: minimumWeightCubed,
                    tolerance: tolerance,
                    message: "Rational Bezier derivative weight bounds underflowed."
                )
            }
            let firstLocal = Self.upwardSum(
                Self.upwardDivide(numeratorFirst, minimumWeight),
                Self.upwardDivide(
                    Self.upwardProduct(value, weightFirst),
                    minimumWeightSquared
                )
            )
            let secondLocal = Self.upwardSum(
                Self.upwardDivide(numeratorSecond, minimumWeight),
                Self.upwardSum(
                    Self.upwardDivide(
                        Self.upwardProduct(
                            2.0,
                            Self.upwardProduct(numeratorFirst, weightFirst)
                        ),
                        minimumWeightSquared
                    ),
                    Self.upwardSum(
                        Self.upwardDivide(
                            Self.upwardProduct(value, weightSecond),
                            minimumWeightSquared
                        ),
                        Self.upwardDivide(
                            Self.upwardProduct(
                                2.0,
                                Self.upwardProduct(
                                    value,
                                    Self.upwardProduct(weightFirst, weightFirst)
                                )
                            ),
                            minimumWeightCubed
                        )
                    )
                )
            )
            firstResult.append(Self.upwardProduct(firstLocal, firstScale))
            secondResult.append(Self.upwardProduct(secondLocal, secondScale))
        }
        first = firstResult
        second = secondResult
    }

    private static func firstDerivativeControlBound(
        _ values: [Double],
        degree: Int
    ) -> Double {
        guard degree > 0 else { return 0.0 }
        var maximum = 0.0
        for index in 0..<degree {
            maximum = max(
                maximum,
                abs(values[index + 1] - values[index]).nextUp
            )
        }
        return upwardProduct(Double(degree), maximum)
    }

    private static func secondDerivativeControlBound(
        _ values: [Double],
        degree: Int
    ) -> Double {
        guard degree > 1 else { return 0.0 }
        var maximum = 0.0
        for index in 0..<(degree - 1) {
            let firstDifference = values[index + 2] - values[index + 1]
            let secondDifference = values[index + 1] - values[index]
            let difference = firstDifference - secondDifference
            let scale = max(
                abs(values[index]),
                abs(values[index + 1]),
                abs(values[index + 2]),
                1.0
            )
            let arithmeticAllowance = (
                Double.ulpOfOne * scale * 32.0
            ).nextUp
            maximum = max(
                maximum,
                (abs(difference) + arithmeticAllowance).nextUp
            )
        }
        return upwardProduct(
            Double(degree * (degree - 1)),
            maximum
        )
    }

    private static func maximumAbsolute(_ values: [Double]) -> Double {
        (values.map(abs).max() ?? 0.0).nextUp
    }

    private static func upwardSum(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs + rhs).nextUp
    }

    private static func upwardProduct(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs * rhs).nextUp
    }

    private static func upwardDivide(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs / rhs).nextUp
    }
}
