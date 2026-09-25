import CADCore
import Foundation

package enum SurfaceBoundaryCertifier {
    package struct Side: Sendable {
        package let lift: SurfaceLiftCurve3D
        package let reversedParameter: Bool
        package let reversedNormal: Bool

        package init(lift: SurfaceLiftCurve3D, reversedParameter: Bool = false, reversedNormal: Bool = false) {
            self.lift = lift
            self.reversedParameter = reversedParameter
            self.reversedNormal = reversedNormal
        }
    }

    package struct Certificate: Sendable {
        package let position: Double
        package let normalChord: Double?
        package let shapeOperator: Double?
        package let inspectedCells: Int
    }

    package static func certify(
        first: Side, second: Side, positionTolerance: Double,
        normalChordTolerance: Double? = nil, shapeOperatorTolerance: Double? = nil,
        maximumCells: Int, maximumDepth: Int, tolerance: ModelingTolerance
    ) throws -> Certificate {
        let limits = [positionTolerance] + (normalChordTolerance.map { [$0] } ?? [])
            + (shapeOperatorTolerance.map { [$0] } ?? [])
        guard limits.allSatisfy({ $0.isFinite && $0 > 0 }),
              shapeOperatorTolerance == nil || normalChordTolerance != nil,
              normalChordTolerance == nil || normalChordTolerance! <= 2,
              maximumCells > 0, maximumDepth >= 0 else {
            throw failure(.invalidInput, "Boundary certification requires finite positive limits and subdivision budgets.")
        }
        let order = shapeOperatorTolerance != nil ? 2 : normalChordTolerance != nil ? 1 : 0
        let a = try Prepared(side: first, order: order, tolerance: tolerance)
        let b = try Prepared(side: second, order: order, tolerance: tolerance)
        var pending = [(lower: 0.0, upper: 1.0, depth: 0)]
        var visited = 0
        var maxima = Array(repeating: 0.0, count: order + 1)
        while let cell = pending.popLast() {
            try Task.checkCancellation()
            guard visited < maximumCells else {
                throw failure(.resourceLimitExceeded, "Boundary certification exhausted its cell budget.")
            }
            visited += 1
            let interval = try ScalarInterval(lower: cell.lower, upper: cell.upper)
            let mid = cell.lower + (cell.upper - cell.lower) * 0.5
            let center = try ScalarInterval(lower: mid.nextDown, upper: mid.nextUp)
            let firstBounds = try a.quantities(over: interval, order: order, tolerance: tolerance)
            let secondBounds = try b.quantities(over: interval, order: order, tolerance: tolerance)
            let firstCenter = try a.quantities(over: center, order: order, tolerance: tolerance)
            let secondCenter = try b.quantities(over: center, order: order, tolerance: tolerance)
            if let firstBounds, let secondBounds, let firstCenter, let secondCenter {
                let radius = OutwardScalarInterval(lower: (cell.lower - mid).nextDown,
                    upper: (cell.upper - mid).nextUp)
                var differences: [OutwardScalarInterval] = []
                for index in firstBounds.indices {
                    differences.append((firstCenter[index].value - secondCenter[index].value)
                        + radius * (firstBounds[index].derivativeU - secondBounds[index].derivativeU))
                }
                let ranges = [0..<3, 3..<6, 6..<15]
                var upperBounds: [Double] = []
                for group in 0...order {
                    var upperSquared = OutwardScalarInterval.exact(0)
                    var lowerSquared = OutwardScalarInterval.exact(0)
                    var centerLowerSquared = OutwardScalarInterval.exact(0)
                    for index in ranges[group] {
                        let bound = differences[index]
                        guard bound.isFinite else {
                            throw failure(.resourceLimitExceeded, "Boundary error enclosure exceeded finite arithmetic range.")
                        }
                        let high = OutwardScalarInterval.exact(bound.absoluteUpperBound)
                        let low = OutwardScalarInterval.exact(bound.absoluteLowerBound)
                        upperSquared = upperSquared + high * high
                        lowerSquared = lowerSquared + low * low
                        let centerDifference = firstCenter[index].value - secondCenter[index].value
                        let witness = OutwardScalarInterval.exact(centerDifference.absoluteLowerBound)
                        centerLowerSquared = centerLowerSquared + witness * witness
                    }
                    let magnitude = sqrt(max(0, upperSquared.upper)).nextUp
                    let upper = group == 1 ? min(2, magnitude) : magnitude
                    let lower = max(0, sqrt(max(0, lowerSquared.lower)).nextDown)
                    guard upper.isFinite else {
                        throw failure(.resourceLimitExceeded, "Boundary error magnitude exceeded finite arithmetic range.")
                    }
                    let centerLower = max(0, sqrt(max(0, centerLowerSquared.lower)).nextDown)
                    guard max(lower, centerLower) <= limits[group] else {
                        throw failure(.classificationFailure, "A boundary interval violates the requested continuity bound.")
                    }
                    upperBounds.append(upper)
                }
                if zip(upperBounds, limits).allSatisfy({ $0 <= $1 }) {
                    for index in maxima.indices { maxima[index] = max(maxima[index], upperBounds[index]) }
                    continue
                }
            }
            guard cell.depth < maximumDepth, mid > cell.lower, mid < cell.upper else {
                throw failure(.resourceLimitExceeded, "Boundary continuity or regularity remains uncertified at the subdivision limit.")
            }
            pending.append((mid, cell.upper, cell.depth + 1))
            pending.append((cell.lower, mid, cell.depth + 1))
        }
        return Certificate(position: maxima[0], normalChord: order >= 1 ? maxima[1] : nil,
            shapeOperator: order >= 2 ? maxima[2] : nil, inspectedCells: visited)
    }

    private struct Prepared {
        let side: Side
        let surface: PreparedSurfaceDifferentialEncloser

        init(side: Side, order: Int, tolerance: ModelingTolerance) throws {
            try side.lift.validate(tolerance: tolerance)
            if case let .bSpline(value) = side.lift.surface {
                for (knots, degree, domain) in [(value.uKnots, value.uDegree, value.uDomain),
                                               (value.vKnots, value.vDegree, value.vDomain)] {
                    guard case let .closed(lower, upper) = domain else {
                        throw failure(.invalidInput, "Boundary certification requires a valid spline domain.")
                    }
                    var index = 0
                    while index < knots.count {
                        var end = index + 1
                        while end < knots.count, knots[end] == knots[index] { end += 1 }
                        if knots[index] > lower, knots[index] < upper, end - index > degree - order {
                            throw failure(.unsupportedCapability, "Boundary certification requires the requested spline smoothness at interior knots.")
                        }
                        index = end
                    }
                }
            }
            self.side = side
            surface = try PreparedSurfaceDifferentialEncloser(surface: side.lift.surface, tolerance: tolerance)
        }

        /// Only value and first boundary derivative of the returned jets are consumed.
        func quantities(over interval: ScalarInterval, order: Int,
                        tolerance: ModelingTolerance) throws -> [SurfaceIntervalJet]? {
            let mapped: ScalarInterval
            if side.reversedParameter {
                let value = OutwardScalarInterval.exact(1)
                    - OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
                mapped = try ScalarInterval(lower: max(0, value.lower), upper: min(1, value.upper))
            } else { mapped = interval }
            guard let uv = try SurfaceParameterIntervalJet.enclose(
                side.lift.parameterCurve, over: mapped, tolerance: tolerance) else {
                throw failure(.unsupportedCapability, "The boundary parameter curve has no certified interval jet.")
            }
            let bounder = SurfaceLiftDifferentialBounder()
            let box = try SurfaceParameterBox(
                u: bounder.nondegenerateRange(ScalarInterval(lower: uv.u.value.lower, upper: uv.u.value.upper),
                    domain: side.lift.surface.uDomain, tolerance: tolerance),
                v: bounder.nondegenerateRange(ScalarInterval(lower: uv.v.value.lower, upper: uv.v.value.upper),
                    domain: side.lift.surface.vDomain, tolerance: tolerance))
            let p = try surface.intervalJet(over: box, tolerance: tolerance)
            var values = [p.x, p.y, p.z]
            if order > 0 {
                let u = p.differentiatedUThroughSecondOrder()
                let v = p.differentiatedVThroughSecondOrder()
                let cross = u.cross(v)
                guard let unit = cross.normalized() else { return nil }
                let normal = side.reversedNormal ? -unit : unit
                values += [normal.x, normal.y, normal.z]
                if order > 1 {
                    guard let inverseDeterminant = cross.dot(cross).reciprocal() else { return nil }
                    let e = u.dot(u), f = u.dot(v), g = v.dot(v)
                    let dualU = (u * g + -(v * f)) * inverseDeterminant
                    let dualV = (v * e + -(u * f)) * inverseDeterminant
                    let l = normal.dot(u.differentiatedUThroughSecondOrder())
                    let m = normal.dot(u.differentiatedVThroughSecondOrder())
                    let n = normal.dot(v.differentiatedVThroughSecondOrder())
                    let first = [dualU.x, dualU.y, dualU.z]
                    let second = [dualV.x, dualV.y, dualV.z]
                    for row in 0..<3 {
                        for column in 0..<3 {
                            values.append(l * first[row] * first[column]
                                + m * (first[row] * second[column] + second[row] * first[column])
                                + n * second[row] * second[column])
                        }
                    }
                }
            }
            let direction = OutwardScalarInterval.exact(side.reversedParameter ? -1 : 1)
            let zero = OutwardScalarInterval.exact(0)
            return values.map { value in
                SurfaceIntervalJet(value: value.value,
                    derivativeU: (value.derivativeU * uv.u.derivativeU + value.derivativeV * uv.v.derivativeU) * direction,
                    derivativeV: zero, secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                    thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
            }
        }
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}
