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
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(bernsteinControlExpansions: controls, uDegree: uDegree, vDegree: vDegree, using: &execution)
    }


    init?(
        bernsteinControlExpansions controls: [[[Double]]],
        uDegree: Int,
        vDegree: Int
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)

        let uPowerRows = try CertifiedAnalyticCurveEvaluation.map(controls, using: &execution) { row, execution in
            try Self.powerCoefficients(row, degree: uDegree, using: &execution)
        }
        for row in uPowerRows {
            try execution.consumeWork(1)
            guard row.count == 3 else { return nil }
        }
        try execution.retainStorage(count: 3, stride: MemoryLayout<[[Double]]>.stride)
        try execution.retainStorage(count: 3, stride: MemoryLayout<[Double]>.stride)
        var coefficients = Array(
            repeating: Array(repeating: [0.0], count: 3),
            count: 3
        )
        for uPower in 0..<3 {
                try execution.consumeWork(1)
            let vPower = try Self.powerCoefficients(
                CertifiedAnalyticCurveEvaluation.map(uPowerRows, using: &execution) { row, _ in row[uPower] },
                degree: vDegree
            , using: &execution)
            guard vPower.count == 3 else {
                return nil
            }
            for vIndex in 0..<3 {
                try execution.consumeWork(1)
                coefficients[uPower][vIndex] = vPower[vIndex]
            }
        }
        for uPower in 0..<3 {
                try execution.consumeWork(1)
            for vPower in 0..<3 where uPower + vPower > 2 {
                try execution.consumeWork(1)
                guard try Self.sign(coefficients[uPower][vPower], using: &execution) == .zero else {
                    return nil
                }
            }
        }
        uu = coefficients[2][0]
        uv = try Self.scaled(coefficients[1][1], by: 0.5, using: &execution)
        vv = coefficients[0][2]
        u = coefficients[1][0]
        v = coefficients[0][1]
        constant = coefficients[0][0]
    }

    func classifiedZeroSet() throws -> ZeroSet? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try classifiedZeroSet(using: &execution)
    }


    func classifiedZeroSet(using execution: inout OriginalQueryExecution) throws -> ZeroSet? {
        try execution.consumeWork(1)

        let determinant = try Self.subtract(
            try Self.multiply(uu, vv, using: &execution),
            try Self.multiply(uv, uv, using: &execution)
        , using: &execution)
        switch try Self.sign(determinant, using: &execution) {
        case .positive, .negative:
            return try classifiedFullRankZeroSet(determinant: determinant, using: &execution)
        case .zero:
            return try classifiedRankOneZeroSet(using: &execution)
        case .indeterminate:
            return nil
        }
    }



    private func classifiedFullRankZeroSet(
        determinant: [Double]
    , using execution: inout OriginalQueryExecution) throws -> ZeroSet? {
        try execution.consumeWork(1)

        let stationaryValueNumerator = try Self.subtract(
            try Self.add(
                try Self.scaled(try Self.multiply(constant, determinant, using: &execution), by: 4.0, using: &execution),
                try Self.scaled(
                    try Self.multiply(try Self.multiply(uv, u, using: &execution), v, using: &execution),
                    by: 2.0
                , using: &execution)
            , using: &execution),
            try Self.add(
                try Self.multiply(vv, try Self.multiply(u, u, using: &execution), using: &execution),
                try Self.multiply(uu, try Self.multiply(v, v, using: &execution), using: &execution)
            , using: &execution)
        , using: &execution)
        guard try Self.sign(stationaryValueNumerator, using: &execution) == .zero else {
            return nil
        }
        let denominator = try Self.scaled(determinant, by: 2.0, using: &execution)
        let uNumerator = try Self.subtract(
            try Self.multiply(uv, v, using: &execution),
            try Self.multiply(vv, u, using: &execution)
        , using: &execution)
        let vNumerator = try Self.subtract(
            try Self.multiply(uv, u, using: &execution),
            try Self.multiply(uu, v, using: &execution)
        , using: &execution)
        guard try Self.isStrictlyInsideUnitInterval(
            numerator: uNumerator,
            denominator: denominator
        , using: &execution), try Self.isStrictlyInsideUnitInterval(
            numerator: vNumerator,
            denominator: denominator
        , using: &execution), let stationary = try Self.quotientPoint(
            uNumerator: uNumerator,
            vNumerator: vNumerator,
            denominator: denominator
        , using: &execution) else {
            return nil
        }
        if try Self.sign(determinant, using: &execution) == .positive {
            return .isolated(stationary)
        }
        guard let lines = try crossingLines(through: stationary, using: &execution) else {
            return nil
        }
        return .crossing(lines.0, lines.1)
    }



    private func classifiedRankOneZeroSet(using execution: inout OriginalQueryExecution) throws -> ZeroSet? {
        try execution.consumeWork(1)

        if try Self.sign(uu, using: &execution) != .zero {
            let rangeCondition = try Self.subtract(
                try Self.multiply(uu, v, using: &execution),
                try Self.multiply(uv, u, using: &execution)
            , using: &execution)
            let vertexValue = try Self.subtract(
                try Self.scaled(try Self.multiply(uu, constant, using: &execution), by: 4.0, using: &execution),
                try Self.multiply(u, u, using: &execution)
            , using: &execution)
            guard try Self.sign(rangeCondition, using: &execution) == .zero,
                  try Self.sign(vertexValue, using: &execution) == .zero else {
                return nil
            }
            return try Self.line(
                a: try Self.scaled(uu, by: 2.0, using: &execution),
                b: try Self.scaled(uv, by: 2.0, using: &execution),
                constant: u
            , using: &execution).map(ZeroSet.line)
        }
        if try Self.sign(vv, using: &execution) != .zero {
            let rangeCondition = try Self.subtract(
                try Self.multiply(vv, u, using: &execution),
                try Self.multiply(uv, v, using: &execution)
            , using: &execution)
            let vertexValue = try Self.subtract(
                try Self.scaled(try Self.multiply(vv, constant, using: &execution), by: 4.0, using: &execution),
                try Self.multiply(v, v, using: &execution)
            , using: &execution)
            guard try Self.sign(rangeCondition, using: &execution) == .zero,
                  try Self.sign(vertexValue, using: &execution) == .zero else {
                return nil
            }
            return try Self.line(
                a: try Self.scaled(uv, by: 2.0, using: &execution),
                b: try Self.scaled(vv, by: 2.0, using: &execution),
                constant: v
            , using: &execution).map(ZeroSet.line)
        }
        return nil
    }



    private func crossingLines(
        through stationary: Point2D
    , using execution: inout OriginalQueryExecution) throws -> (Line, Line)? {
        try execution.consumeWork(1)

        let hessianXX = try Self.estimate(try Self.scaled(uu, by: 2.0, using: &execution), using: &execution)
        let hessianXY = try Self.estimate(try Self.scaled(uv, by: 2.0, using: &execution), using: &execution)
        let hessianYY = try Self.estimate(try Self.scaled(vv, by: 2.0, using: &execution), using: &execution)
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
              let firstDirection = try Self.eigenvector(
                  xx: hessianXX,
                  xy: hessianXY,
                  yy: hessianYY,
                  eigenvalue: firstEigenvalue
              , using: &execution) else {
            return nil
        }
        let secondDirection = Point2D(
            x: -firstDirection.y,
            y: firstDirection.x
        )
        let firstScale = sqrt(secondEigenvalue)
        let secondScale = sqrt(-firstEigenvalue)
        guard let positive = try Self.normalized(Point2D(
            x: firstDirection.x * firstScale
                + secondDirection.x * secondScale,
            y: firstDirection.y * firstScale
                + secondDirection.y * secondScale
        ), using: &execution), let negative = try Self.normalized(Point2D(
            x: firstDirection.x * firstScale
                - secondDirection.x * secondScale,
            y: firstDirection.y * firstScale
                - secondDirection.y * secondScale
        ), using: &execution), abs(positive.x * negative.y - positive.y * negative.x)
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
    , using execution: inout OriginalQueryExecution) throws -> Point2D? {
        try execution.consumeWork(1)

        let denominatorEstimate = try estimate(denominator, using: &execution)
        let uEstimate = try estimate(uNumerator, using: &execution)
        let vEstimate = try estimate(vNumerator, using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)

        let denominatorSign = try sign(denominator, using: &execution)
        guard denominatorSign == .positive || denominatorSign == .negative else {
            return false
        }
        let orientedNumerator = denominatorSign == .positive
            ? numerator
            : try scaled(numerator, by: -1.0, using: &execution)
        let orientedDenominator = denominatorSign == .positive
            ? denominator
            : try scaled(denominator, by: -1.0, using: &execution)
        return try sign(orientedNumerator, using: &execution) == .positive
            && sign(subtract(orientedDenominator, orientedNumerator, using: &execution), using: &execution) == .positive
    }



    private static func line(
        a: [Double],
        b: [Double],
        constant: [Double]
    , using execution: inout OriginalQueryExecution) throws -> Line? {
        try execution.consumeWork(1)

        let aEstimate = try estimate(a, using: &execution)
        let bEstimate = try estimate(b, using: &execution)
        let constantEstimate = try estimate(constant, using: &execution)
        let squaredNormal = aEstimate * aEstimate + bEstimate * bEstimate
        guard aEstimate.isFinite,
              bEstimate.isFinite,
              constantEstimate.isFinite,
              squaredNormal.isFinite,
              squaredNormal > 0.0,
              let direction = try normalized(Point2D(
                  x: -bEstimate,
                  y: aEstimate
              ), using: &execution) else {
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
    , using execution: inout OriginalQueryExecution) throws -> Point2D? {
        try execution.consumeWork(1)

        let first = Point2D(x: xy, y: eigenvalue - xx)
        let second = Point2D(x: eigenvalue - yy, y: xy)
        return try normalized(
            try squaredLength(first, using: &execution) >= squaredLength(second, using: &execution) ? first : second
        , using: &execution)
    }



    private static func normalized(_ value: Point2D, using execution: inout OriginalQueryExecution) throws -> Point2D? {
        try execution.consumeWork(1)

        let magnitude = hypot(value.x, value.y)
        guard magnitude.isFinite, magnitude > 0.0 else {
            return nil
        }
        return Point2D(x: value.x / magnitude, y: value.y / magnitude)
    }



    private static func squaredLength(_ value: Point2D, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return value.x * value.x + value.y * value.y
    }



    private static func powerCoefficients(
        _ controls: [[Double]],
        degree: Int
    , using execution: inout OriginalQueryExecution) throws -> [[Double]] {
        try execution.consumeWork(1)

        try execution.retainStorage(count: 3, stride: MemoryLayout<[Double]>.stride)
        switch degree {
        case 1 where controls.count == 2:
            return [
                controls[0],
                try subtract(controls[1], controls[0], using: &execution),
                [0.0],
            ]
        case 2 where controls.count == 3:
            return [
                controls[0],
                try scaled(try subtract(controls[1], controls[0], using: &execution), by: 2.0, using: &execution),
                try add(
                    try subtract(controls[0], try scaled(controls[1], by: 2.0, using: &execution), using: &execution),
                    controls[2]
                , using: &execution),
            ]
        default:
            return []
        }
    }



    private static func sign(_ value: [Double], using execution: inout OriginalQueryExecution) throws -> RobustSign {
        try execution.consumeWork(1)
        return try FloatingPointExpansion.sign(value, using: &execution)
    }



    private static func estimate(_ value: [Double], using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        return try FloatingPointExpansion.estimate(value, using: &execution)
    }



    private static func add(_ lhs: [Double], _ rhs: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        return try FloatingPointExpansion.sum(lhs, rhs, using: &execution)
    }



    private static func subtract(_ lhs: [Double], _ rhs: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        return try FloatingPointExpansion.subtract(lhs, rhs, using: &execution)
    }



    private static func multiply(_ lhs: [Double], _ rhs: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        return try FloatingPointExpansion.product(lhs, rhs, using: &execution)
    }



    private static func scaled(_ value: [Double], by scale: Double, using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        return try FloatingPointExpansion.product(value, OriginalCoefficientAllocation.singleton(scale, using: &execution), using: &execution)
    }
}
