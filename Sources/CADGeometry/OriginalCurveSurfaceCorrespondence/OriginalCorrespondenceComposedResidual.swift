import CADCore

/// Whole native tensor lift minus spatial curve, retaining homogeneous coefficient correlation.
struct OriginalCorrespondenceComposedResidual {
    struct Proof {
        let upper: Double
        let cells: Int
    }
    private struct Cell { let lower: Double; let upper: Double; let depth: Int }
    private struct Bound { let upper: Double?; let centerLower: Double }
    private typealias Polynomial = [OutwardScalarInterval]
    private typealias Homogeneous = [Polynomial]

    func certify(curve: BSplineCurve3D, start: Double, end: Double,
                 surface: Surface3D, parameterCurve: SurfaceParameterCurve,
                 requested: Double, budget: inout OriginalCorrespondenceBudget) throws -> Proof? {
        guard case let .bSpline(support) = surface,
              degreeFold(support.uKnots, degree: 3, controls: support.uControlPointCount) else { return nil }
        let parameter: BSplineCurve2D?
        if case let .bSpline(value) = parameterCurve { parameter = value } else { parameter = nil }
        let spatialPieces = (curve.controlPoints.count - 1) / curve.degree
        let parameterPieces = parameter.map { ($0.controlPoints.count - 1) / $0.degree } ?? 1
        let count = spatialPieces.addingReportingOverflow(parameterPieces)
        let rootCapacity = count.partialValue.multipliedReportingOverflow(by: 2)
        guard !count.overflow, !rootCapacity.overflow else { throw exhausted(budget) }
        let capacity = rootCapacity.partialValue.addingReportingOverflow(2)
        guard !capacity.overflow else { throw exhausted(budget) }
        // Fixed degree caps bound every live polynomial. Root and stack storage are separate.
        let scratch = 128 * (23 * 2 + 4) + (budget.maximumDepth + 2) * 3
        let slots = capacity.partialValue.addingReportingOverflow(scratch)
        guard !slots.overflow else { throw exhausted(budget) }
        try budget.admitTemporaryScalars(slots.partialValue)
        var roots = [0.0, 1.0]
        try budget.charge(2)
        try appendRoots(knots: curve.knots, degree: curve.degree, controls: curve.controlPoints.count,
                        start: start, end: end, roots: &roots, budget: &budget)
        if let parameter {
            try appendRoots(knots: parameter.knots, degree: parameter.degree, controls: parameter.controlPoints.count,
                start: parameter.knots[parameter.degree], end: parameter.knots[parameter.controlPoints.count],
                roots: &roots, budget: &budget)
        }
        try roots.sort {
            try budget.charge()
            return $0 < $1
        }
        let origin = curve.controlPoints[0]
        var achieved = 0.0, inspected = 0
        for index in 1..<roots.count where roots[index - 1] < roots[index] {
            try budget.charge()
            var pending = [Cell(lower: roots[index - 1], upper: roots[index], depth: 0)]
            while let cell = pending.popLast() {
                try budget.charge(); inspected += 1
                let bound = try enclosure(curve: curve, start: start, end: end, support: support,
                    parameterCurve: parameterCurve, parameter: parameter, origin: origin,
                    cell: cell, budget: &budget)
                guard bound.centerLower <= requested else {
                    throw OriginalCorrespondenceBudget.failure(.topologyFailure, budget.tolerance,
                        "An original homogeneous curve/surface residual violates the requested deviation.",
                        residual: bound.centerLower)
                }
                if let upper = bound.upper, upper <= requested { achieved = max(achieved, upper); continue }
                let mid = cell.lower + (cell.upper - cell.lower) * 0.5
                guard cell.depth < budget.maximumDepth, mid > cell.lower, mid < cell.upper else {
                    throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, budget.tolerance,
                        "Original homogeneous correspondence remains unproved at the subdivision limit.")
                }
                try budget.charge(2)
                pending.append(Cell(lower: mid, upper: cell.upper, depth: cell.depth + 1))
                pending.append(Cell(lower: cell.lower, upper: mid, depth: cell.depth + 1))
            }
        }
        return Proof(upper: achieved, cells: inspected)
    }

    private func degreeFold(_ knots: [Double], degree: Int, controls: Int) -> Bool {
        guard degree > 0, (controls - 1) % degree == 0 else { return false }
        var index = degree + 1
        while index < controls {
            var end = index + 1
            while end < controls, knots[end] == knots[index] { end += 1 }
            guard end - index == degree else { return false }
            index = end
        }
        return true
    }

    private func appendRoots(knots: [Double], degree: Int, controls: Int,
                             start: Double, end: Double, roots: inout [Double],
                             budget: inout OriginalCorrespondenceBudget) throws {
        let lower = min(start, end), upper = max(start, end)
        var index = degree + 1
        while index < controls {
            let knot = knots[index]
            if knot > lower, knot < upper {
                try budget.charge(2)
                let numerator = OutwardScalarInterval.exact(knot) - .exact(start)
                let denominator = OutwardScalarInterval.exact(end) - .exact(start)
                let value = try quotient(numerator, by: denominator, tolerance: budget.tolerance)
                guard value.isFinite else { throw exhausted(budget) }
                // The original knot is strictly inside the trim, independently proving its
                // exact preimage belongs to (0,1). Intersect only this arithmetic overhang.
                roots.append(max(0, value.lower)); roots.append(min(1, value.upper))
            }
            repeat { index += 1 } while index < controls && knots[index] == knot
        }
    }

    private func enclosure(curve: BSplineCurve3D, start: Double, end: Double,
                           support: BSplineSurface3D, parameterCurve: SurfaceParameterCurve,
                           parameter: BSplineCurve2D?, origin: Point3D,
                           cell: Cell, budget: inout OriginalCorrespondenceBudget) throws -> Bound {
        let time = affine(start, end, cell: cell)
        let range = time[0].union(time[1])
        let spatialIndices = pieces(knots: curve.knots, degree: curve.degree,
            controls: curve.controlPoints.count, range: range)
        let parameterTime: Polynomial?
        let parameterIndices: Range<Int>
        if let parameter {
            let values = affine(parameter.knots[parameter.degree], parameter.knots[parameter.controlPoints.count], cell: cell)
            parameterTime = values
            parameterIndices = pieces(knots: parameter.knots, degree: parameter.degree,
                controls: parameter.controlPoints.count, range: values[0].union(values[1]))
        } else { parameterTime = nil; parameterIndices = 0..<1 }
        var upper = 0.0, complete = true
        var center: [OutwardScalarInterval]?
        for pcIndex in parameterIndices {
            try budget.charge()
            let pc: Homogeneous
            if let parameter, let parameterTime {
                pc = try parameterPolynomials(parameter, piece: pcIndex, time: parameterTime, tolerance: budget.tolerance)
            } else {
                pc = try affineParameter(parameterCurve, cell: cell, tolerance: budget.tolerance)
            }
            guard let pcWeight = positiveHull(pc[2]) else { complete = false; continue }
            let uRange = try quotient(hull(pc[0]), by: pcWeight, tolerance: budget.tolerance)
            let supportIndices = pieces(knots: support.uKnots, degree: 3,
                controls: support.uControlPointCount, range: uRange)
            for supportIndex in supportIndices {
                try budget.charge()
                let reference = try supportPolynomials(support, piece: supportIndex, parameter: pc,
                    origin: origin, tolerance: budget.tolerance)
                guard let referenceWeight = positiveHull(reference[3]) else { complete = false; continue }
                for spatialIndex in spatialIndices {
                    try budget.charge()
                    let spatial = try spatialPolynomials(curve, piece: spatialIndex, time: time,
                        origin: origin, tolerance: budget.tolerance)
                    guard let spatialWeight = positiveHull(spatial[3]) else { complete = false; continue }
                    let denominator = spatialWeight * referenceWeight
                    guard denominator.isFinite, denominator.lower > 0 else { complete = false; continue }
                    var centers: [OutwardScalarInterval] = []
                    var squared = OutwardScalarInterval.exact(0)
                    let centerWeight = evaluate(spatial[3], at: .exact(0.5)) * evaluate(reference[3], at: .exact(0.5))
                    for axis in 0..<3 {
                        let residual = subtract(multiply(spatial[axis], reference[3]), multiply(reference[axis], spatial[3]))
                        let value = try quotient(.exact(hull(residual).absoluteUpperBound), by: denominator, tolerance: budget.tolerance)
                        squared = squared + value * value
                        centers.append(try quotient(evaluate(residual, at: .exact(0.5)), by: centerWeight, tolerance: budget.tolerance))
                    }
                    let candidate = max(0, squared.upper).squareRoot().nextUp
                    guard candidate.isFinite else { complete = false; continue }
                    upper = max(upper, candidate)
                    if let previous = center { center = zip(previous, centers).map { $0.union($1) } } else { center = centers }
                }
            }
        }
        guard let center else { return Bound(upper: nil, centerLower: 0) }
        var squared = OutwardScalarInterval.exact(0)
        for value in center { let low = OutwardScalarInterval.exact(value.absoluteLowerBound); squared = squared + low * low }
        let lower = max(0, max(0, squared.lower).squareRoot().nextDown)
        guard lower.isFinite else { throw exhausted(budget) }
        return Bound(upper: complete ? upper : nil, centerLower: complete ? lower : 0)
    }

    private func pieces(knots: [Double], degree: Int, controls: Int,
                        range: OutwardScalarInterval) -> Range<Int> {
        let count = (controls - 1) / degree
        var lower = 0, upper = count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if knots[degree + degree * middle + 1] < range.lower { lower = middle + 1 } else { upper = middle }
        }
        let first = lower
        while lower < count, knots[degree + degree * lower] <= range.upper { lower += 1 }
        return first..<lower
    }

    private func affine(_ start: Double, _ end: Double, cell: Cell) -> Polynomial {
        let delta = OutwardScalarInterval.exact(end) - .exact(start)
        return [.exact(start) + delta * .exact(cell.lower), .exact(start) + delta * .exact(cell.upper)]
    }

    private func spatialPolynomials(_ curve: BSplineCurve3D, piece: Int, time: Polynomial,
                                    origin: Point3D, tolerance: ModelingTolerance) throws -> Homogeneous {
        let first = piece * curve.degree
        let low = curve.knots[first + curve.degree], high = curve.knots[first + curve.degree + 1]
        var values = Array(repeating: Polynomial(), count: 4)
        for index in first...(first + curve.degree) {
            let point = curve.controlPoints[index], weight = OutwardScalarInterval.exact(curve.weights[index])
            values[0].append((.exact(point.x) - .exact(origin.x)) * weight)
            values[1].append((.exact(point.y) - .exact(origin.y)) * weight)
            values[2].append((.exact(point.z) - .exact(origin.z)) * weight)
            values[3].append(weight)
        }
        return try values.map { try restricted($0, time: time, lower: low, upper: high, tolerance: tolerance) }
    }

    private func parameterPolynomials(_ curve: BSplineCurve2D, piece: Int, time: Polynomial,
                                      tolerance: ModelingTolerance) throws -> Homogeneous {
        let first = piece * curve.degree
        let low = curve.knots[first + curve.degree], high = curve.knots[first + curve.degree + 1]
        var values = Array(repeating: Polynomial(), count: 3)
        for index in first...(first + curve.degree) {
            let point = curve.controlPoints[index], weight = OutwardScalarInterval.exact(curve.weights[index])
            values[0].append(.exact(point.x) * weight); values[1].append(.exact(point.y) * weight); values[2].append(weight)
        }
        return try values.map { try restricted($0, time: time, lower: low, upper: high, tolerance: tolerance) }
    }

    private func affineParameter(_ curve: SurfaceParameterCurve, cell: Cell,
                                 tolerance: ModelingTolerance) throws -> Homogeneous {
        switch curve {
        case let .constantU(u, start, end): return [[.exact(u)], affine(start, end, cell: cell), [.exact(1)]]
        case let .constantV(v, start, end): return [affine(start, end, cell: cell), [.exact(v)], [.exact(1)]]
        case let .affine(origin, direction, start, end):
            let time = affine(start, end, cell: cell)
            return [time.map { .exact(origin.x) + .exact(direction.x) * $0 },
                    time.map { .exact(origin.y) + .exact(direction.y) * $0 }, [.exact(1)]]
        default: throw OriginalCorrespondenceBudget.failure(.unsupportedCapability, tolerance, "No original affine parameter composition.")
        }
    }

    private func supportPolynomials(_ surface: BSplineSurface3D, piece: Int,
                                    parameter: Homogeneous, origin: Point3D,
                                    tolerance: ModelingTolerance) throws -> Homogeneous {
        let first = piece * 3, low = surface.uKnots[first + 3], high = surface.uKnots[first + 4]
        let vLow = surface.vKnots[1], vHigh = surface.vKnots[2]
        let a = try divide(subtract(parameter[0], scale(parameter[2], .exact(low))),
            by: .exact(high) - .exact(low), tolerance: tolerance)
        let b = subtract(parameter[2], a)
        let c = try divide(subtract(parameter[1], scale(parameter[2], .exact(vLow))),
            by: .exact(vHigh) - .exact(vLow), tolerance: tolerance)
        let d = subtract(parameter[2], c)
        let ap = [Polynomial([.exact(1)]), a, multiply(a, a), multiply(multiply(a, a), a)]
        let bp = [Polynomial([.exact(1)]), b, multiply(b, b), multiply(multiply(b, b), b)]
        var result = Array(repeating: Polynomial([.exact(0)]), count: 4)
        var commonWeight: Double? = surface.weights[0][first]
        for row in 0..<2 { for column in 0..<4 {
            let factor = scale(multiply(multiply(ap[column], bp[3 - column]), row == 0 ? d : c), .exact(column == 0 || column == 3 ? 1 : 3))
            let point = surface.controlPoints[row][first + column]
            let weight = surface.weights[row][first + column]
            if commonWeight != weight { commonWeight = nil }
            let w = OutwardScalarInterval.exact(weight)
            for axis in 0..<3 {
                let coordinate: OutwardScalarInterval
                switch axis {
                case 0: coordinate = .exact(point.x) - .exact(origin.x)
                case 1: coordinate = .exact(point.y) - .exact(origin.y)
                default: coordinate = .exact(point.z) - .exact(origin.z)
                }
                result[axis] = add(result[axis], scale(factor, coordinate * w))
            }
            result[3] = add(result[3], scale(factor, w))
        } }
        if let commonWeight {
            let squared = multiply(parameter[2], parameter[2])
            result[3] = scale(multiply(squared, squared), .exact(commonWeight))
        }
        return result
    }

    private func restricted(_ polynomial: Polynomial, time: Polynomial, lower: Double, upper: Double,
                            tolerance: ModelingTolerance) throws -> Polynomial {
        let width = OutwardScalarInterval.exact(upper) - .exact(lower)
        let a = try quotient(time[0] - .exact(lower), by: width, tolerance: tolerance)
        let b = try quotient(time[1] - .exact(lower), by: width, tolerance: tolerance)
        let degree = polynomial.count - 1
        var result: Polynomial = []
        for output in 0...degree {
            var values = polynomial
            for order in 0..<degree {
                let argument = order < degree - output ? a : b
                for index in 0..<(degree - order) {
                    values[index] = (.exact(1) - argument) * values[index] + argument * values[index + 1]
                }
            }
            result.append(values[0])
        }
        return result
    }

    private func evaluate(_ polynomial: Polynomial, at argument: OutwardScalarInterval) -> OutwardScalarInterval {
        var values = polynomial
        if polynomial.count > 1 {
            for order in 1..<polynomial.count {
                for index in 0..<(polynomial.count - order) {
                    values[index] = (.exact(1) - argument) * values[index] + argument * values[index + 1]
                }
            }
        }
        return values[0]
    }

    private func multiply(_ left: Polynomial, _ right: Polynomial) -> Polynomial {
        let p = left.count - 1, q = right.count - 1
        var result = Array(repeating: OutwardScalarInterval.exact(0), count: p + q + 1)
        for i in 0...p { for j in 0...q {
            let ratio = tryRatio(binomial(p, i) * binomial(q, j), binomial(p + q, i + j))
            result[i + j] = result[i + j] + left[i] * right[j] * ratio
        } }
        return result
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        if k == 0 || k == n { return 1 }
        var value = 1.0
        for index in 1...min(k, n - k) { value = value * Double(n - index + 1) / Double(index) }
        return value
    }

    private func tryRatio(_ numerator: Double, _ denominator: Double) -> OutwardScalarInterval {
        // Degrees <=22 have exact integer binomials/products (<2^53); division is outward.
        let value = numerator / denominator
        return OutwardScalarInterval(lower: value.nextDown, upper: value.nextUp)
    }

    private func elevate(_ values: Polynomial, to degree: Int) -> Polynomial {
        var result = values
        while result.count <= degree {
            let n = result.count
            var next = Array(repeating: OutwardScalarInterval.exact(0), count: n + 1)
            next[0] = result[0]; next[n] = result[n - 1]
            if n > 1 { for index in 1..<n {
                let a = tryRatio(Double(index), Double(n))
                let b = tryRatio(Double(n - index), Double(n))
                next[index] = a * result[index - 1] + b * result[index]
            } }
            result = next
        }
        return result
    }

    private func add(_ left: Polynomial, _ right: Polynomial) -> Polynomial {
        let degree = max(left.count, right.count) - 1
        return zip(elevate(left, to: degree), elevate(right, to: degree)).map { $0 + $1 }
    }
    private func subtract(_ left: Polynomial, _ right: Polynomial) -> Polynomial {
        let degree = max(left.count, right.count) - 1
        return zip(elevate(left, to: degree), elevate(right, to: degree)).map { $0 - $1 }
    }
    private func scale(_ value: Polynomial, _ factor: OutwardScalarInterval) -> Polynomial { value.map { $0 * factor } }
    private func divide(_ value: Polynomial, by denominator: OutwardScalarInterval,
                        tolerance: ModelingTolerance) throws -> Polynomial {
        try value.map { try quotient($0, by: denominator, tolerance: tolerance) }
    }
    private func quotient(_ value: OutwardScalarInterval, by denominator: OutwardScalarInterval,
                          tolerance: ModelingTolerance) throws -> OutwardScalarInterval {
        guard let result = value.divided(by: denominator), result.isFinite else {
            throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, tolerance,
                "Original homogeneous division has no finite nonzero interval denominator.")
        }
        return result
    }
    private func hull(_ value: Polynomial) -> OutwardScalarInterval {
        value.dropFirst().reduce(value[0]) { $0.union($1) }
    }
    private func positiveHull(_ value: Polynomial) -> OutwardScalarInterval? {
        let result = hull(value)
        return result.isFinite && result.lower > 0 ? result : nil
    }
    private func exhausted(_ budget: OriginalCorrespondenceBudget) -> KernelError {
        OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, budget.tolerance,
            "Original homogeneous correspondence exhausted bounded numeric construction.")
    }
}
