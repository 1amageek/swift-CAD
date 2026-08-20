import CADCore
import Foundation

struct RationalBezierCurveSurfaceDifferencePatch: Sendable {
    enum RootCertificate: Sendable, Equatable {
        case excluded
        case unique
        case unresolved
    }

    enum SplitDirection: Sendable {
        case curve
        case surfaceU
        case surfaceV
    }

    private struct OutwardInterval: Sendable {
        let lower: Double
        let upper: Double

        init(_ value: Double) {
            lower = value.nextDown
            upper = value.nextUp
        }

        private init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func enclosing(_ lower: Double, _ upper: Double) -> OutwardInterval {
            OutwardInterval(lower: lower.nextDown, upper: upper.nextUp)
        }

        static func + (
            lhs: OutwardInterval,
            rhs: OutwardInterval
        ) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func - (
            lhs: OutwardInterval,
            rhs: OutwardInterval
        ) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower - rhs.upper).nextDown,
                upper: (lhs.upper - rhs.lower).nextUp
            )
        }

        static func * (
            lhs: OutwardInterval,
            rhs: OutwardInterval
        ) -> OutwardInterval {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return OutwardInterval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
            )
        }

        func midpoint(with other: OutwardInterval) -> OutwardInterval {
            let half = OutwardInterval(0.5)
            return self * half + other * half
        }

        var midpoint: Double {
            lower + (upper - lower) * 0.5
        }

        var isFinite: Bool {
            lower.isFinite && upper.isFinite
        }
    }

    private struct IntervalVector: Sendable {
        let x: OutwardInterval
        let y: OutwardInterval
        let z: OutwardInterval

        func midpoint(with other: IntervalVector) -> IntervalVector {
            IntervalVector(
                x: x.midpoint(with: other.x),
                y: y.midpoint(with: other.y),
                z: z.midpoint(with: other.z)
            )
        }

        func subtracting(
            _ other: IntervalVector,
            scale: Double
        ) -> IntervalVector {
            let scaleInterval = OutwardInterval(scale)
            return IntervalVector(
                x: (other.x - x) * scaleInterval,
                y: (other.y - y) * scaleInterval,
                z: (other.z - z) * scaleInterval
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite
        }
    }

    private struct DoubleVector: Sendable {
        let x: Double
        let y: Double
        let z: Double

        func dot(_ other: DoubleVector) -> Double {
            x * other.x + y * other.y + z * other.z
        }

        func cross(_ other: DoubleVector) -> DoubleVector {
            DoubleVector(
                x: y * other.z - z * other.y,
                y: z * other.x - x * other.z,
                z: x * other.y - y * other.x
            )
        }

        func divided(by value: Double) -> DoubleVector {
            DoubleVector(x: x / value, y: y / value, z: z / value)
        }

        var length: Double {
            sqrt(dot(self))
        }

        subscript(_ index: Int) -> Double {
            switch index {
            case 0: x
            case 1: y
            default: z
            }
        }
    }

    private let controlNet: [[[IntervalVector]]]
    private let hasConstantSurfaceVTranslation: Bool
    let curveLower: Double
    let curveUpper: Double
    let surfaceULower: Double
    let surfaceUUpper: Double
    let surfaceVLower: Double
    let surfaceVUpper: Double

    init(
        curve: RationalBezierCurvePatch3D,
        surface: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    ) throws {
        guard curve.controlPoints.count == curve.weights.count,
              curve.controlPoints.isEmpty == false,
              surface.controlPoints.count == surface.weights.count,
              surface.controlPoints.isEmpty == false,
              surface.controlPoints.indices.allSatisfy({
                  surface.controlPoints[$0].count == surface.weights[$0].count
                      && surface.controlPoints[$0].isEmpty == false
              }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier difference construction requires matching non-empty control data."
            )
        }
        let result = curve.controlPoints.indices.map { curveIndex in
            surface.controlPoints.indices.map { surfaceVIndex in
                surface.controlPoints[surfaceVIndex].indices.map { surfaceUIndex in
                    Self.differenceCoefficient(
                        curvePoint: curve.controlPoints[curveIndex],
                        curveWeight: curve.weights[curveIndex],
                        surfacePoint: surface.controlPoints[surfaceVIndex][surfaceUIndex],
                        surfaceWeight: surface.weights[surfaceVIndex][surfaceUIndex]
                    )
                }
            }
        }
        guard result.flatMap({ $0 }).flatMap({ $0 }).allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational Bezier curve-surface difference exceeded finite interval arithmetic."
            )
        }
        controlNet = result
        hasConstantSurfaceVTranslation = Self.isConstantSurfaceVTranslation(surface)
        curveLower = curve.lower
        curveUpper = curve.upper
        surfaceULower = surface.uLower
        surfaceUUpper = surface.uUpper
        surfaceVLower = surface.vLower
        surfaceVUpper = surface.vUpper
    }

    private init(
        controlNet: [[[IntervalVector]]],
        hasConstantSurfaceVTranslation: Bool,
        curveLower: Double,
        curveUpper: Double,
        surfaceULower: Double,
        surfaceUUpper: Double,
        surfaceVLower: Double,
        surfaceVUpper: Double
    ) {
        self.controlNet = controlNet
        self.hasConstantSurfaceVTranslation = hasConstantSurfaceVTranslation
        self.curveLower = curveLower
        self.curveUpper = curveUpper
        self.surfaceULower = surfaceULower
        self.surfaceUUpper = surfaceUUpper
        self.surfaceVLower = surfaceVLower
        self.surfaceVUpper = surfaceVUpper
    }

    func excludesZero() -> Bool {
        excludesZero { $0.x }
            || excludesZero { $0.y }
            || excludesZero { $0.z }
    }

    func rootCertificate() -> RootCertificate {
        guard excludesZero() == false else { return .excluded }
        let value = centerValue()
        let curveDerivative = derivativeBounds(direction: .curve)
        let surfaceUDerivative = derivativeBounds(direction: .surfaceU)
        let surfaceVDerivative = derivativeBounds(direction: .surfaceV)
        let midpointColumns = [
            DoubleVector(
                x: curveDerivative.x.midpoint,
                y: curveDerivative.y.midpoint,
                z: curveDerivative.z.midpoint
            ),
            DoubleVector(
                x: surfaceUDerivative.x.midpoint,
                y: surfaceUDerivative.y.midpoint,
                z: surfaceUDerivative.z.midpoint
            ),
            DoubleVector(
                x: surfaceVDerivative.x.midpoint,
                y: surfaceVDerivative.y.midpoint,
                z: surfaceVDerivative.z.midpoint
            ),
        ]
        guard let inverse = inverseRows(columns: midpointColumns) else {
            return .unresolved
        }
        let jacobian = [
            [curveDerivative.x, surfaceUDerivative.x, surfaceVDerivative.x],
            [curveDerivative.y, surfaceUDerivative.y, surfaceVDerivative.y],
            [curveDerivative.z, surfaceUDerivative.z, surfaceVDerivative.z],
        ]
        let functionValue = [value.x, value.y, value.z]
        let radius = OutwardInterval.enclosing(-0.5, 0.5)
        var krawczyk: [OutwardInterval] = []
        for row in 0..<3 {
            var component = OutwardInterval(0.5)
            for inner in 0..<3 {
                component = component
                    - OutwardInterval(inverse[row][inner]) * functionValue[inner]
            }
            for column in 0..<3 {
                var preconditioned = OutwardInterval(0.0)
                for inner in 0..<3 {
                    preconditioned = preconditioned
                        + OutwardInterval(inverse[row][inner]) * jacobian[inner][column]
                }
                let identity = OutwardInterval(row == column ? 1.0 : 0.0)
                component = component + (identity - preconditioned) * radius
            }
            krawczyk.append(component)
        }
        if krawczyk.contains(where: { $0.upper < 0.0 || $0.lower > 1.0 }) {
            return .excluded
        }
        if krawczyk.allSatisfy({ $0.lower > 0.0 && $0.upper < 1.0 }) {
            return .unique
        }
        return .unresolved
    }

    func subdivided(
        direction: SplitDirection
    ) -> [RationalBezierCurveSurfaceDifferencePatch] {
        let halves: (
            lower: [[[IntervalVector]]],
            upper: [[[IntervalVector]]]
        )
        switch direction {
        case .curve:
            halves = splitCurve()
        case .surfaceU:
            halves = splitSurfaceU()
        case .surfaceV:
            halves = splitSurfaceV()
        }
        let curveMiddle = curveLower + (curveUpper - curveLower) * 0.5
        let surfaceUMiddle = surfaceULower
            + (surfaceUUpper - surfaceULower) * 0.5
        let surfaceVMiddle = surfaceVLower
            + (surfaceVUpper - surfaceVLower) * 0.5
        switch direction {
        case .curve:
            return [
                replacing(
                    controlNet: halves.lower,
                    curveBounds: (curveLower, curveMiddle),
                    surfaceUBounds: (surfaceULower, surfaceUUpper),
                    surfaceVBounds: (surfaceVLower, surfaceVUpper)
                ),
                replacing(
                    controlNet: halves.upper,
                    curveBounds: (curveMiddle, curveUpper),
                    surfaceUBounds: (surfaceULower, surfaceUUpper),
                    surfaceVBounds: (surfaceVLower, surfaceVUpper)
                ),
            ]
        case .surfaceU:
            return [
                replacing(
                    controlNet: halves.lower,
                    curveBounds: (curveLower, curveUpper),
                    surfaceUBounds: (surfaceULower, surfaceUMiddle),
                    surfaceVBounds: (surfaceVLower, surfaceVUpper)
                ),
                replacing(
                    controlNet: halves.upper,
                    curveBounds: (curveLower, curveUpper),
                    surfaceUBounds: (surfaceUMiddle, surfaceUUpper),
                    surfaceVBounds: (surfaceVLower, surfaceVUpper)
                ),
            ]
        case .surfaceV:
            return [
                replacing(
                    controlNet: halves.lower,
                    curveBounds: (curveLower, curveUpper),
                    surfaceUBounds: (surfaceULower, surfaceUUpper),
                    surfaceVBounds: (surfaceVLower, surfaceVMiddle)
                ),
                replacing(
                    controlNet: halves.upper,
                    curveBounds: (curveLower, curveUpper),
                    surfaceUBounds: (surfaceULower, surfaceUUpper),
                    surfaceVBounds: (surfaceVMiddle, surfaceVUpper)
                ),
            ]
        }
    }

    func splitDirection(at depth: Int) -> SplitDirection {
        if hasConstantSurfaceVTranslation {
            return depth.isMultiple(of: 2) ? .curve : .surfaceU
        }
        switch depth % 3 {
        case 0:
            return .curve
        case 1:
            return .surfaceU
        default:
            return .surfaceV
        }
    }

    private static func isConstantSurfaceVTranslation(
        _ surface: RationalBezierSurfacePatch3D
    ) -> Bool {
        guard surface.controlPoints.count == 2,
              surface.weights.count == 2,
              surface.controlPoints[0].count == surface.controlPoints[1].count,
              let firstLower = surface.controlPoints[0].first,
              let firstUpper = surface.controlPoints[1].first else {
            return false
        }
        let scale = max(
            1.0,
            surface.controlPoints.flatMap { $0 }.reduce(0.0) { result, point in
                max(result, abs(point.x), abs(point.y), abs(point.z))
            },
            surface.weights.flatMap { $0 }.reduce(0.0) { result, weight in
                max(result, abs(weight))
            }
        )
        // Exact ruled surfaces are recovered from endpoint derivatives by
        // Bezier decomposition. That reconstruction can differ by a handful
        // of floating-point operations even though the source surface has an
        // exact constant translation in V. This arithmetic-scale bound only
        // recognizes roundoff-equivalent nets; it is independent of the
        // modeling tolerance and cannot turn a geometrically varying surface
        // into a ruled one.
        let resolution = Double.ulpOfOne * scale * 8_192.0
        guard surface.weights[0].indices.allSatisfy({ index in
            abs(surface.weights[0][index] - surface.weights[1][index])
                <= resolution
        }) else {
            return false
        }
        let translation = firstUpper - firstLower
        guard translation.length > resolution else { return false }
        return surface.controlPoints[0].indices.allSatisfy { index in
            let candidate = surface.controlPoints[1][index]
                - surface.controlPoints[0][index]
            return abs(candidate.x - translation.x) <= resolution
                && abs(candidate.y - translation.y) <= resolution
                && abs(candidate.z - translation.z) <= resolution
        }
    }

    private static func differenceCoefficient(
        curvePoint: Point3D,
        curveWeight: Double,
        surfacePoint: Point3D,
        surfaceWeight: Double
    ) -> IntervalVector {
        let curveWeightInterval = OutwardInterval(curveWeight)
        let surfaceWeightInterval = OutwardInterval(surfaceWeight)
        func coordinate(_ curveValue: Double, _ surfaceValue: Double) -> OutwardInterval {
            let weightedCurve = OutwardInterval(curveValue) * curveWeightInterval
            let weightedSurface = OutwardInterval(surfaceValue) * surfaceWeightInterval
            return weightedCurve * surfaceWeightInterval
                - weightedSurface * curveWeightInterval
        }
        return IntervalVector(
            x: coordinate(curvePoint.x, surfacePoint.x),
            y: coordinate(curvePoint.y, surfacePoint.y),
            z: coordinate(curvePoint.z, surfacePoint.z)
        )
    }

    private func centerValue() -> IntervalVector {
        let afterCurve = controlNet[0].indices.map { vIndex in
            controlNet[0][vIndex].indices.map { uIndex in
                evaluatedMidpoint(controlNet.map { $0[vIndex][uIndex] })
            }
        }
        let afterSurfaceV = afterCurve[0].indices.map { uIndex in
            evaluatedMidpoint(afterCurve.map { $0[uIndex] })
        }
        return evaluatedMidpoint(afterSurfaceV)
    }

    private func derivativeBounds(
        direction: SplitDirection
    ) -> IntervalVector {
        let derivativeNet: [[[IntervalVector]]]
        switch direction {
        case .curve:
            let degree = Double(controlNet.count - 1)
            derivativeNet = (0..<(controlNet.count - 1)).map { curveIndex in
                controlNet[curveIndex].indices.map { vIndex in
                    controlNet[curveIndex][vIndex].indices.map { uIndex in
                        controlNet[curveIndex][vIndex][uIndex].subtracting(
                            controlNet[curveIndex + 1][vIndex][uIndex],
                            scale: degree
                        )
                    }
                }
            }
        case .surfaceU:
            let degree = Double(controlNet[0][0].count - 1)
            derivativeNet = controlNet.indices.map { curveIndex in
                controlNet[curveIndex].indices.map { vIndex in
                    (0..<(controlNet[curveIndex][vIndex].count - 1)).map { uIndex in
                        controlNet[curveIndex][vIndex][uIndex].subtracting(
                            controlNet[curveIndex][vIndex][uIndex + 1],
                            scale: degree
                        )
                    }
                }
            }
        case .surfaceV:
            let degree = Double(controlNet[0].count - 1)
            derivativeNet = controlNet.indices.map { curveIndex in
                (0..<(controlNet[curveIndex].count - 1)).map { vIndex in
                    controlNet[curveIndex][vIndex].indices.map { uIndex in
                        controlNet[curveIndex][vIndex][uIndex].subtracting(
                            controlNet[curveIndex][vIndex + 1][uIndex],
                            scale: degree
                        )
                    }
                }
            }
        }
        return enclosing(derivativeNet.flatMap { $0 }.flatMap { $0 })
    }

    private func enclosing(_ values: [IntervalVector]) -> IntervalVector {
        IntervalVector(
            x: OutwardInterval.enclosing(
                values.map { $0.x.lower }.min() ?? -.infinity,
                values.map { $0.x.upper }.max() ?? .infinity
            ),
            y: OutwardInterval.enclosing(
                values.map { $0.y.lower }.min() ?? -.infinity,
                values.map { $0.y.upper }.max() ?? .infinity
            ),
            z: OutwardInterval.enclosing(
                values.map { $0.z.lower }.min() ?? -.infinity,
                values.map { $0.z.upper }.max() ?? .infinity
            )
        )
    }

    private func inverseRows(columns: [DoubleVector]) -> [DoubleVector]? {
        guard columns.count == 3 else { return nil }
        let firstCross = columns[1].cross(columns[2])
        let determinant = columns[0].dot(firstCross)
        let scale = max(
            columns[0].length,
            max(columns[1].length, columns[2].length)
        )
        let determinantFloor = max(
            pow(scale, 3.0) * Double.ulpOfOne * 1_024.0,
            Double.leastNonzeroMagnitude
        )
        guard determinant.isFinite,
              scale.isFinite,
              abs(determinant) > determinantFloor else {
            return nil
        }
        return [
            firstCross.divided(by: determinant),
            columns[2].cross(columns[0]).divided(by: determinant),
            columns[0].cross(columns[1]).divided(by: determinant),
        ]
    }

    private func excludesZero(
        component: (IntervalVector) -> OutwardInterval
    ) -> Bool {
        let coefficients = controlNet.flatMap { $0 }.flatMap { $0 }.map(component)
        let minimum = coefficients.map(\.lower).min() ?? -.infinity
        let maximum = coefficients.map(\.upper).max() ?? .infinity
        return minimum > 0.0 || maximum < 0.0
    }

    private func splitCurve() -> (
        lower: [[[IntervalVector]]],
        upper: [[[IntervalVector]]]
    ) {
        var lower = controlNet
        var upper = controlNet
        for vIndex in controlNet[0].indices {
            for uIndex in controlNet[0][vIndex].indices {
                let halves = split(controlNet.map { $0[vIndex][uIndex] })
                for curveIndex in controlNet.indices {
                    lower[curveIndex][vIndex][uIndex] = halves.lower[curveIndex]
                    upper[curveIndex][vIndex][uIndex] = halves.upper[curveIndex]
                }
            }
        }
        return (lower, upper)
    }

    private func splitSurfaceU() -> (
        lower: [[[IntervalVector]]],
        upper: [[[IntervalVector]]]
    ) {
        var lower = controlNet
        var upper = controlNet
        for curveIndex in controlNet.indices {
            for vIndex in controlNet[curveIndex].indices {
                let halves = split(controlNet[curveIndex][vIndex])
                for uIndex in controlNet[curveIndex][vIndex].indices {
                    lower[curveIndex][vIndex][uIndex] = halves.lower[uIndex]
                    upper[curveIndex][vIndex][uIndex] = halves.upper[uIndex]
                }
            }
        }
        return (lower, upper)
    }

    private func splitSurfaceV() -> (
        lower: [[[IntervalVector]]],
        upper: [[[IntervalVector]]]
    ) {
        var lower = controlNet
        var upper = controlNet
        for curveIndex in controlNet.indices {
            for uIndex in controlNet[curveIndex][0].indices {
                let halves = split(
                    controlNet[curveIndex].map { $0[uIndex] }
                )
                for vIndex in controlNet[curveIndex].indices {
                    lower[curveIndex][vIndex][uIndex] = halves.lower[vIndex]
                    upper[curveIndex][vIndex][uIndex] = halves.upper[vIndex]
                }
            }
        }
        return (lower, upper)
    }

    private func split(
        _ values: [IntervalVector]
    ) -> (lower: [IntervalVector], upper: [IntervalVector]) {
        guard values.count > 1 else { return (values, values) }
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].midpoint(with: previous[index + 1])
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func evaluatedMidpoint(
        _ values: [IntervalVector]
    ) -> IntervalVector {
        guard values.count > 1 else { return values[0] }
        var level = values
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index].midpoint(with: level[index + 1])
            }
        }
        return level[0]
    }

    private func replacing(
        controlNet: [[[IntervalVector]]],
        curveBounds: (Double, Double),
        surfaceUBounds: (Double, Double),
        surfaceVBounds: (Double, Double)
    ) -> RationalBezierCurveSurfaceDifferencePatch {
        RationalBezierCurveSurfaceDifferencePatch(
            controlNet: controlNet,
            hasConstantSurfaceVTranslation: hasConstantSurfaceVTranslation,
            curveLower: curveBounds.0,
            curveUpper: curveBounds.1,
            surfaceULower: surfaceUBounds.0,
            surfaceUUpper: surfaceUBounds.1,
            surfaceVLower: surfaceVBounds.0,
            surfaceVUpper: surfaceVBounds.1
        )
    }
}
