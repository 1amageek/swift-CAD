import Foundation
import CADCore

struct ExactQuadraticPolynomial2D: Sendable {
    struct Line: Sendable {
        let origin: Point2D
        let direction: Point2D
    }

    enum ZeroSet: Sendable {
        case isolated(Point2D)
        case line(Line)
        case crossing(Line, Line)
    }

    private let uu: [Double]
    private let uv: [Double]
    private let vv: [Double]
    private let u: [Double]
    private let v: [Double]
    private let constant: [Double]

    init?(
        bernsteinControlExpansions controls: [[[Double]]],
        uDegree: Int,
        vDegree: Int
    ) {
        let uPowerRows = controls.map {
            Self.powerCoefficients($0, degree: uDegree)
        }
        guard uPowerRows.allSatisfy({ $0.count == 3 }) else {
            return nil
        }
        var coefficients = Array(
            repeating: Array(repeating: [0.0], count: 3),
            count: 3
        )
        for uPower in 0..<3 {
            let vPower = Self.powerCoefficients(
                uPowerRows.map { $0[uPower] },
                degree: vDegree
            )
            guard vPower.count == 3 else {
                return nil
            }
            for vIndex in 0..<3 {
                coefficients[uPower][vIndex] = vPower[vIndex]
            }
        }
        for uPower in 0..<3 {
            for vPower in 0..<3 where uPower + vPower > 2 {
                guard Self.sign(coefficients[uPower][vPower]) == .zero else {
                    return nil
                }
            }
        }
        uu = coefficients[2][0]
        uv = Self.scaled(coefficients[1][1], by: 0.5)
        vv = coefficients[0][2]
        u = coefficients[1][0]
        v = coefficients[0][1]
        constant = coefficients[0][0]
    }

    func classifiedZeroSet() -> ZeroSet? {
        let determinant = Self.subtract(
            Self.multiply(uu, vv),
            Self.multiply(uv, uv)
        )
        switch Self.sign(determinant) {
        case .positive, .negative:
            return classifiedFullRankZeroSet(determinant: determinant)
        case .zero:
            return classifiedRankOneZeroSet()
        case .indeterminate:
            return nil
        }
    }

    private func classifiedFullRankZeroSet(
        determinant: [Double]
    ) -> ZeroSet? {
        let stationaryValueNumerator = Self.subtract(
            Self.add(
                Self.scaled(Self.multiply(constant, determinant), by: 4.0),
                Self.scaled(
                    Self.multiply(Self.multiply(uv, u), v),
                    by: 2.0
                )
            ),
            Self.add(
                Self.multiply(vv, Self.multiply(u, u)),
                Self.multiply(uu, Self.multiply(v, v))
            )
        )
        guard Self.sign(stationaryValueNumerator) == .zero else {
            return nil
        }
        let denominator = Self.scaled(determinant, by: 2.0)
        let uNumerator = Self.subtract(
            Self.multiply(uv, v),
            Self.multiply(vv, u)
        )
        let vNumerator = Self.subtract(
            Self.multiply(uv, u),
            Self.multiply(uu, v)
        )
        guard Self.isStrictlyInsideUnitInterval(
            numerator: uNumerator,
            denominator: denominator
        ), Self.isStrictlyInsideUnitInterval(
            numerator: vNumerator,
            denominator: denominator
        ), let stationary = Self.quotientPoint(
            uNumerator: uNumerator,
            vNumerator: vNumerator,
            denominator: denominator
        ) else {
            return nil
        }
        if Self.sign(determinant) == .positive {
            return .isolated(stationary)
        }
        guard let lines = crossingLines(through: stationary) else {
            return nil
        }
        return .crossing(lines.0, lines.1)
    }

    private func classifiedRankOneZeroSet() -> ZeroSet? {
        if Self.sign(uu) != .zero {
            let rangeCondition = Self.subtract(
                Self.multiply(uu, v),
                Self.multiply(uv, u)
            )
            let vertexValue = Self.subtract(
                Self.scaled(Self.multiply(uu, constant), by: 4.0),
                Self.multiply(u, u)
            )
            guard Self.sign(rangeCondition) == .zero,
                  Self.sign(vertexValue) == .zero else {
                return nil
            }
            return Self.line(
                a: Self.scaled(uu, by: 2.0),
                b: Self.scaled(uv, by: 2.0),
                constant: u
            ).map(ZeroSet.line)
        }
        if Self.sign(vv) != .zero {
            let rangeCondition = Self.subtract(
                Self.multiply(vv, u),
                Self.multiply(uv, v)
            )
            let vertexValue = Self.subtract(
                Self.scaled(Self.multiply(vv, constant), by: 4.0),
                Self.multiply(v, v)
            )
            guard Self.sign(rangeCondition) == .zero,
                  Self.sign(vertexValue) == .zero else {
                return nil
            }
            return Self.line(
                a: Self.scaled(uv, by: 2.0),
                b: Self.scaled(vv, by: 2.0),
                constant: v
            ).map(ZeroSet.line)
        }
        return nil
    }

    private func crossingLines(
        through stationary: Point2D
    ) -> (Line, Line)? {
        let hessianXX = Self.estimate(Self.scaled(uu, by: 2.0))
        let hessianXY = Self.estimate(Self.scaled(uv, by: 2.0))
        let hessianYY = Self.estimate(Self.scaled(vv, by: 2.0))
        guard hessianXX.isFinite,
              hessianXY.isFinite,
              hessianYY.isFinite else {
            return nil
        }
        let halfDifference = (hessianXX - hessianYY) * 0.5
        let radius = hypot(halfDifference, hessianXY)
        let center = (hessianXX + hessianYY) * 0.5
        let firstEigenvalue = center - radius
        let secondEigenvalue = center + radius
        guard firstEigenvalue.isFinite,
              secondEigenvalue.isFinite,
              firstEigenvalue < 0.0,
              secondEigenvalue > 0.0,
              let firstDirection = Self.eigenvector(
                  xx: hessianXX,
                  xy: hessianXY,
                  yy: hessianYY,
                  eigenvalue: firstEigenvalue
              ) else {
            return nil
        }
        let secondDirection = Point2D(
            x: -firstDirection.y,
            y: firstDirection.x
        )
        let firstScale = sqrt(secondEigenvalue)
        let secondScale = sqrt(-firstEigenvalue)
        guard let positive = Self.normalized(Point2D(
            x: firstDirection.x * firstScale
                + secondDirection.x * secondScale,
            y: firstDirection.y * firstScale
                + secondDirection.y * secondScale
        )), let negative = Self.normalized(Point2D(
            x: firstDirection.x * firstScale
                - secondDirection.x * secondScale,
            y: firstDirection.y * firstScale
                - secondDirection.y * secondScale
        )), abs(positive.x * negative.y - positive.y * negative.x)
            > Double.ulpOfOne * 4_096.0 else {
            return nil
        }
        return (
            Line(origin: stationary, direction: positive),
            Line(origin: stationary, direction: negative)
        )
    }

    private static func quotientPoint(
        uNumerator: [Double],
        vNumerator: [Double],
        denominator: [Double]
    ) -> Point2D? {
        let denominatorEstimate = estimate(denominator)
        let uEstimate = estimate(uNumerator)
        let vEstimate = estimate(vNumerator)
        guard denominatorEstimate.isFinite,
              denominatorEstimate != 0.0,
              uEstimate.isFinite,
              vEstimate.isFinite else {
            return nil
        }
        let result = Point2D(
            x: uEstimate / denominatorEstimate,
            y: vEstimate / denominatorEstimate
        )
        guard result.x.isFinite,
              result.y.isFinite,
              result.x > 0.0,
              result.x < 1.0,
              result.y > 0.0,
              result.y < 1.0 else {
            return nil
        }
        return result
    }

    private static func isStrictlyInsideUnitInterval(
        numerator: [Double],
        denominator: [Double]
    ) -> Bool {
        let denominatorSign = sign(denominator)
        guard denominatorSign == .positive || denominatorSign == .negative else {
            return false
        }
        let orientedNumerator = denominatorSign == .positive
            ? numerator
            : scaled(numerator, by: -1.0)
        let orientedDenominator = denominatorSign == .positive
            ? denominator
            : scaled(denominator, by: -1.0)
        return sign(orientedNumerator) == .positive
            && sign(subtract(orientedDenominator, orientedNumerator)) == .positive
    }

    private static func line(
        a: [Double],
        b: [Double],
        constant: [Double]
    ) -> Line? {
        let aEstimate = estimate(a)
        let bEstimate = estimate(b)
        let constantEstimate = estimate(constant)
        let squaredNormal = aEstimate * aEstimate + bEstimate * bEstimate
        guard aEstimate.isFinite,
              bEstimate.isFinite,
              constantEstimate.isFinite,
              squaredNormal.isFinite,
              squaredNormal > 0.0,
              let direction = normalized(Point2D(
                  x: -bEstimate,
                  y: aEstimate
              )) else {
            return nil
        }
        let scale = -constantEstimate / squaredNormal
        let origin = Point2D(
            x: aEstimate * scale,
            y: bEstimate * scale
        )
        guard origin.x.isFinite, origin.y.isFinite else {
            return nil
        }
        return Line(origin: origin, direction: direction)
    }

    private static func eigenvector(
        xx: Double,
        xy: Double,
        yy: Double,
        eigenvalue: Double
    ) -> Point2D? {
        let first = Point2D(x: xy, y: eigenvalue - xx)
        let second = Point2D(x: eigenvalue - yy, y: xy)
        return normalized(
            squaredLength(first) >= squaredLength(second) ? first : second
        )
    }

    private static func normalized(_ value: Point2D) -> Point2D? {
        let magnitude = hypot(value.x, value.y)
        guard magnitude.isFinite, magnitude > 0.0 else {
            return nil
        }
        return Point2D(x: value.x / magnitude, y: value.y / magnitude)
    }

    private static func squaredLength(_ value: Point2D) -> Double {
        value.x * value.x + value.y * value.y
    }

    private static func powerCoefficients(
        _ controls: [[Double]],
        degree: Int
    ) -> [[Double]] {
        switch degree {
        case 1 where controls.count == 2:
            return [
                controls[0],
                subtract(controls[1], controls[0]),
                [0.0],
            ]
        case 2 where controls.count == 3:
            return [
                controls[0],
                scaled(subtract(controls[1], controls[0]), by: 2.0),
                add(
                    subtract(controls[0], scaled(controls[1], by: 2.0)),
                    controls[2]
                ),
            ]
        default:
            return []
        }
    }

    private static func sign(_ value: [Double]) -> RobustSign {
        FloatingPointExpansion.sign(value)
    }

    private static func estimate(_ value: [Double]) -> Double {
        FloatingPointExpansion.estimate(value)
    }

    private static func add(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        FloatingPointExpansion.sum(lhs, rhs)
    }

    private static func subtract(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        FloatingPointExpansion.subtract(lhs, rhs)
    }

    private static func multiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        FloatingPointExpansion.product(lhs, rhs)
    }

    private static func scaled(_ value: [Double], by scale: Double) -> [Double] {
        FloatingPointExpansion.product(value, [scale])
    }
}
