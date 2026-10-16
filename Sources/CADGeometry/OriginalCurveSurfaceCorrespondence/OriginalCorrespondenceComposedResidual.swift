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
                 requested: Double, policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws -> Proof? {
        try execution.consumeWork(1)
        guard case let .bSpline(support) = surface,
              try degreeFold(support.uKnots, degree: 3, controls: support.uControlPointCount, using: &execution) else { return nil }
        let parameter: BSplineCurve2D?
        if case let .bSpline(value) = parameterCurve { parameter = value } else { parameter = nil }
        let spatialPieces = (curve.controlPoints.count - 1) / curve.degree
        let parameterPieces = parameter.map { ($0.controlPoints.count - 1) / $0.degree } ?? 1
        let count = spatialPieces.addingReportingOverflow(parameterPieces)
        let rootCapacity = count.partialValue.multipliedReportingOverflow(by: 2)
        guard !count.overflow, !rootCapacity.overflow else { throw exhausted(policy) }
        let capacity = rootCapacity.partialValue.addingReportingOverflow(2)
        guard !capacity.overflow else { throw exhausted(policy) }
        // Fixed degree caps bound every live polynomial. Root and stack storage are separate.
        let scratch = 128 * (23 * 2 + 4) + (policy.maximumDepth + 2) * 3
        let slots = capacity.partialValue.addingReportingOverflow(scratch)
        guard !slots.overflow else { throw exhausted(policy) }
        try policy.admitTemporaryScalars(slots.partialValue, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: capacity.partialValue, of: Double.self, using: &execution)
        var roots = [0.0, 1.0]
        roots.reserveCapacity(capacity.partialValue)
        try policy.charge(2, using: &execution)
        try appendRoots(knots: curve.knots, degree: curve.degree, controls: curve.controlPoints.count,
                        start: start, end: end, roots: &roots, policy: policy, using: &execution)
        if let parameter {
            try appendRoots(knots: parameter.knots, degree: parameter.degree, controls: parameter.controlPoints.count,
                start: parameter.knots[parameter.degree], end: parameter.knots[parameter.controlPoints.count],
                roots: &roots, policy: policy, using: &execution)
        }
        try roots.sort {
            try policy.charge(using: &execution)
            return $0 < $1
        }
        let origin = curve.controlPoints[0]
        var achieved = 0.0, inspected = 0
        for index in 1..<roots.count where roots[index - 1] < roots[index] {
            try policy.charge(using: &execution)
            try OriginalCoefficientAllocation.reserve(count: policy.maximumDepth + 2, of: Cell.self, using: &execution)
            var pending: [Cell] = []
            pending.reserveCapacity(policy.maximumDepth + 2)
            pending.append(Cell(lower: roots[index - 1], upper: roots[index], depth: 0))
            while let cell = pending.popLast() {
                try policy.charge(using: &execution); inspected += 1
                let bound = try enclosure(curve: curve, start: start, end: end, support: support,
                    parameterCurve: parameterCurve, parameter: parameter, origin: origin,
                    cell: cell, policy: policy, using: &execution)
                guard bound.centerLower <= requested else {
                    throw OriginalCorrespondencePolicy.failure(.topologyFailure, policy.tolerance,
                        "An original homogeneous curve/surface residual violates the requested deviation.",
                        residual: bound.centerLower)
                }
                if let upper = bound.upper, upper <= requested { achieved = max(achieved, upper); continue }
                let mid = cell.lower + (cell.upper - cell.lower) * 0.5
                guard cell.depth < policy.maximumDepth, mid > cell.lower, mid < cell.upper else {
                    throw OriginalCorrespondencePolicy.failure(.resourceLimitExceeded, policy.tolerance,
                        "Original homogeneous correspondence remains unproved at the subdivision limit.")
                }
                try policy.charge(2, using: &execution)
                pending.append(Cell(lower: mid, upper: cell.upper, depth: cell.depth + 1))
                pending.append(Cell(lower: cell.lower, upper: mid, depth: cell.depth + 1))
            }
        }
        return Proof(upper: achieved, cells: inspected)
    }

    private func degreeFold(_ knots: [Double], degree: Int, controls: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        guard degree > 0, (controls - 1) % degree == 0 else { return false }
        var index = degree + 1
        while index < controls {
            try execution.consumeWork(1)
            var end = index + 1
            while end < controls, knots[end] == knots[index] { try execution.consumeWork(1); end += 1 }
            guard end - index == degree else { return false }
            index = end
        }
        return true
    }

    private func appendRoots(knots: [Double], degree: Int, controls: Int,
                             start: Double, end: Double, roots: inout [Double],
                             policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let lower = min(start, end), upper = max(start, end)
        var index = degree + 1
        while index < controls {
            let knot = knots[index]
            if knot > lower, knot < upper {
                try policy.charge(2, using: &execution)
                let numerator = OutwardScalarInterval.exact(knot) - .exact(start)
                let denominator = OutwardScalarInterval.exact(end) - .exact(start)
                let value = try quotient(numerator, by: denominator, tolerance: policy.tolerance, using: &execution)
                guard value.isFinite else { throw exhausted(policy) }
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
                           cell: Cell, policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws -> Bound {
        try execution.consumeWork(1)
        let time = try affine(start, end, cell: cell, using: &execution)
        let range = time[0].union(time[1])
        let spatialIndices = try pieces(knots: curve.knots, degree: curve.degree,
            controls: curve.controlPoints.count, range: range, using: &execution)
        let parameterTime: Polynomial?
        let parameterIndices: Range<Int>
        if let parameter {
            let values = try affine(parameter.knots[parameter.degree], parameter.knots[parameter.controlPoints.count], cell: cell, using: &execution)
            parameterTime = values
            parameterIndices = try pieces(knots: parameter.knots, degree: parameter.degree,
                controls: parameter.controlPoints.count, range: values[0].union(values[1]), using: &execution)
        } else { parameterTime = nil; parameterIndices = 0..<1 }
        var upper = 0.0, complete = true
        var center: [OutwardScalarInterval]?
        for pcIndex in parameterIndices {
            try policy.charge(using: &execution)
            let pc: Homogeneous
            if let parameter, let parameterTime {
                pc = try parameterPolynomials(parameter, piece: pcIndex, time: parameterTime, tolerance: policy.tolerance, using: &execution)
            } else {
                pc = try affineParameter(parameterCurve, cell: cell, tolerance: policy.tolerance, using: &execution)
            }
            guard let pcWeight = try positiveHull(pc[2], using: &execution) else { complete = false; continue }
            let uRange = try quotient(try hull(pc[0], using: &execution), by: pcWeight, tolerance: policy.tolerance, using: &execution)
            let supportIndices = try pieces(knots: support.uKnots, degree: 3,
                controls: support.uControlPointCount, range: uRange, using: &execution)
            for supportIndex in supportIndices {
                try policy.charge(using: &execution)
                let reference = try supportPolynomials(support, piece: supportIndex, parameter: pc,
                    origin: origin, tolerance: policy.tolerance, using: &execution)
                guard let referenceWeight = try positiveHull(reference[3], using: &execution) else { complete = false; continue }
                for spatialIndex in spatialIndices {
                    try policy.charge(using: &execution)
                    let spatial = try spatialPolynomials(curve, piece: spatialIndex, time: time,
                        origin: origin, tolerance: policy.tolerance, using: &execution)
                    guard let spatialWeight = try positiveHull(spatial[3], using: &execution) else { complete = false; continue }
                    let denominator = spatialWeight * referenceWeight
                    guard denominator.isFinite, denominator.lower > 0 else { complete = false; continue }
                    try OriginalCoefficientAllocation.reserve(count: 3, of: OutwardScalarInterval.self, using: &execution)
                    var centers: [OutwardScalarInterval] = []
                    centers.reserveCapacity(3)
                    var squared = OutwardScalarInterval.exact(0)
                    let centerWeight = try evaluate(spatial[3], at: .exact(0.5), using: &execution) * evaluate(reference[3], at: .exact(0.5), using: &execution)
                    for axis in 0..<3 {
                        let residual = try subtract(try multiply(spatial[axis], reference[3], using: &execution), try multiply(reference[axis], spatial[3], using: &execution), using: &execution)
                        let value = try quotient(.exact(try hull(residual, using: &execution).absoluteUpperBound), by: denominator, tolerance: policy.tolerance, using: &execution)
                        squared = squared + value * value
                        centers.append(try quotient(try evaluate(residual, at: .exact(0.5), using: &execution), by: centerWeight, tolerance: policy.tolerance, using: &execution))
                    }
                    let candidate = max(0, squared.upper).squareRoot().nextUp
                    guard candidate.isFinite else { complete = false; continue }
                    upper = max(upper, candidate)
                    if let previous = center { try OriginalCoefficientAllocation.reserve(count: previous.count, of: OutwardScalarInterval.self, using: &execution); center = zip(previous, centers).map { $0.union($1) } } else { center = centers }
                }
            }
        }
        guard let center else { return Bound(upper: nil, centerLower: 0) }
        var squared = OutwardScalarInterval.exact(0)
        for value in center { let low = OutwardScalarInterval.exact(value.absoluteLowerBound); squared = squared + low * low }
        let lower = max(0, max(0, squared.lower).squareRoot().nextDown)
        guard lower.isFinite else { throw exhausted(policy) }
        return Bound(upper: complete ? upper : nil, centerLower: complete ? lower : 0)
    }

    private func pieces(knots: [Double], degree: Int, controls: Int,
                        range: OutwardScalarInterval, using execution: inout OriginalQueryExecution) throws -> Range<Int> {
        try execution.consumeWork(1)
        let count = (controls - 1) / degree
        var lower = 0, upper = count
        while lower < upper {
            try execution.consumeWork(1)
            let middle = lower + (upper - lower) / 2
            if knots[degree + degree * middle + 1] < range.lower { lower = middle + 1 } else { upper = middle }
        }
        let first = lower
        while lower < count, knots[degree + degree * lower] <= range.upper { try execution.consumeWork(1); lower += 1 }
        return first..<lower
    }

    private func affine(_ start: Double, _ end: Double, cell: Cell, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        let delta = OutwardScalarInterval.exact(end) - .exact(start)
        try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
        return [.exact(start) + delta * .exact(cell.lower), .exact(start) + delta * .exact(cell.upper)]
    }

    private func spatialPolynomials(_ curve: BSplineCurve3D, piece: Int, time: Polynomial,
                                    origin: Point3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Homogeneous {
        try execution.consumeWork(1)
        let first = piece * curve.degree
        let low = curve.knots[first + curve.degree], high = curve.knots[first + curve.degree + 1]
        try OriginalCoefficientAllocation.reserve(count: 4, of: Polynomial.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 4 * (curve.degree + 1), of: OutwardScalarInterval.self, using: &execution)
        var values = Array(repeating: Polynomial(), count: 4)
        for index in values.indices { values[index].reserveCapacity(curve.degree + 1) }
        for index in first...(first + curve.degree) {
            let point = curve.controlPoints[index], weight = OutwardScalarInterval.exact(curve.weights[index])
            values[0].append((.exact(point.x) - .exact(origin.x)) * weight)
            values[1].append((.exact(point.y) - .exact(origin.y)) * weight)
            values[2].append((.exact(point.z) - .exact(origin.z)) * weight)
            values[3].append(weight)
        }
        try OriginalCoefficientAllocation.reserve(count: values.count, of: Polynomial.self, using: &execution)
        return try values.map { try restricted($0, time: time, lower: low, upper: high, tolerance: tolerance, using: &execution) }
    }

    private func parameterPolynomials(_ curve: BSplineCurve2D, piece: Int, time: Polynomial,
                                      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Homogeneous {
        try execution.consumeWork(1)
        let first = piece * curve.degree
        let low = curve.knots[first + curve.degree], high = curve.knots[first + curve.degree + 1]
        try OriginalCoefficientAllocation.reserve(count: 3, of: Polynomial.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 3 * (curve.degree + 1), of: OutwardScalarInterval.self, using: &execution)
        var values = Array(repeating: Polynomial(), count: 3)
        for index in values.indices { values[index].reserveCapacity(curve.degree + 1) }
        for index in first...(first + curve.degree) {
            let point = curve.controlPoints[index], weight = OutwardScalarInterval.exact(curve.weights[index])
            values[0].append(.exact(point.x) * weight); values[1].append(.exact(point.y) * weight); values[2].append(weight)
        }
        try OriginalCoefficientAllocation.reserve(count: values.count, of: Polynomial.self, using: &execution)
        return try values.map { try restricted($0, time: time, lower: low, upper: high, tolerance: tolerance, using: &execution) }
    }

    private func affineParameter(_ curve: SurfaceParameterCurve, cell: Cell,
                                 tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Homogeneous {
        try execution.consumeWork(1)
        switch curve {
        case let .constantU(u, start, end):
            try OriginalCoefficientAllocation.reserve(count: 3, of: Polynomial.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
            return [[.exact(u)], try affine(start, end, cell: cell, using: &execution), [.exact(1)]]
        case let .constantV(v, start, end):
            try OriginalCoefficientAllocation.reserve(count: 3, of: Polynomial.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
            return [try affine(start, end, cell: cell, using: &execution), [.exact(v)], [.exact(1)]]
        case let .affine(origin, direction, start, end):
            try OriginalCoefficientAllocation.reserve(count: 3, of: Polynomial.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: 5, of: OutwardScalarInterval.self, using: &execution)
            let time = try affine(start, end, cell: cell, using: &execution)
            return [time.map { .exact(origin.x) + .exact(direction.x) * $0 },
                    time.map { .exact(origin.y) + .exact(direction.y) * $0 }, [.exact(1)]]
        default: throw OriginalCorrespondencePolicy.failure(.unsupportedCapability, tolerance, "No original affine parameter composition.")
        }
    }

    private func supportPolynomials(_ surface: BSplineSurface3D, piece: Int,
                                    parameter: Homogeneous, origin: Point3D,
                                    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Homogeneous {
        try execution.consumeWork(1)
        let first = piece * 3, low = surface.uKnots[first + 3], high = surface.uKnots[first + 4]
        let vLow = surface.vKnots[1], vHigh = surface.vKnots[2]
        let a = try divide(try subtract(parameter[0], try scale(parameter[2], .exact(low), using: &execution), using: &execution),
            by: .exact(high) - .exact(low), tolerance: tolerance, using: &execution)
        let b = try subtract(parameter[2], a, using: &execution)
        let c = try divide(try subtract(parameter[1], try scale(parameter[2], .exact(vLow), using: &execution), using: &execution),
            by: .exact(vHigh) - .exact(vLow), tolerance: tolerance, using: &execution)
        let d = try subtract(parameter[2], c, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 8, of: Polynomial.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
        let ap = [Polynomial([.exact(1)]), a, try multiply(a, a, using: &execution), try multiply(try multiply(a, a, using: &execution), a, using: &execution)]
        let bp = [Polynomial([.exact(1)]), b, try multiply(b, b, using: &execution), try multiply(try multiply(b, b, using: &execution), b, using: &execution)]
        try OriginalCoefficientAllocation.reserve(count: 4, of: Polynomial.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 4, of: OutwardScalarInterval.self, using: &execution)
        var result = Array(repeating: Polynomial([.exact(0)]), count: 4)
        var commonWeight: Double? = surface.weights[0][first]
        for row in 0..<2 { for column in 0..<4 {
            let factor = try scale(try multiply(try multiply(ap[column], bp[3 - column], using: &execution), row == 0 ? d : c, using: &execution), .exact(column == 0 || column == 3 ? 1 : 3), using: &execution)
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
                result[axis] = try add(result[axis], try scale(factor, coordinate * w, using: &execution), using: &execution)
            }
            result[3] = try add(result[3], try scale(factor, w, using: &execution), using: &execution)
        } }
        if let commonWeight {
            let squared = try multiply(parameter[2], parameter[2], using: &execution)
            result[3] = try scale(try multiply(squared, squared, using: &execution), .exact(commonWeight), using: &execution)
        }
        return result
    }

    private func restricted(_ polynomial: Polynomial, time: Polynomial, lower: Double, upper: Double,
                            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        let width = OutwardScalarInterval.exact(upper) - .exact(lower)
        let a = try quotient(time[0] - .exact(lower), by: width, tolerance: tolerance, using: &execution)
        let b = try quotient(time[1] - .exact(lower), by: width, tolerance: tolerance, using: &execution)
        let degree = polynomial.count - 1
        try OriginalCoefficientAllocation.reserve(count: polynomial.count, of: OutwardScalarInterval.self, using: &execution)
        var result: Polynomial = []
        result.reserveCapacity(polynomial.count)
        for output in 0...degree {
            if degree > 0 {
                try OriginalCoefficientAllocation.reserve(count: polynomial.count, of: OutwardScalarInterval.self, using: &execution)
            }
            var values = polynomial
            for order in 0..<degree {
                let argument = order < degree - output ? a : b
                for index in 0..<(degree - order) {
                    try execution.consumeWork(1)
                    values[index] = (.exact(1) - argument) * values[index] + argument * values[index + 1]
                }
            }
            result.append(values[0])
        }
        return result
    }

    private func evaluate(_ polynomial: Polynomial, at argument: OutwardScalarInterval, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try execution.consumeWork(1)
        var values = polynomial
        if polynomial.count > 1 {
            try OriginalCoefficientAllocation.reserve(count: polynomial.count, of: OutwardScalarInterval.self, using: &execution)
            for order in 1..<polynomial.count {
                for index in 0..<(polynomial.count - order) {
                    try execution.consumeWork(1)
                    values[index] = (.exact(1) - argument) * values[index] + argument * values[index + 1]
                }
            }
        }
        return values[0]
    }

    private func multiply(_ left: Polynomial, _ right: Polynomial, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        let p = left.count - 1, q = right.count - 1
        try OriginalCoefficientAllocation.reserve(count: p + q + 1, of: OutwardScalarInterval.self, using: &execution)
        var result = Array(repeating: OutwardScalarInterval.exact(0), count: p + q + 1)
        for i in 0...p { for j in 0...q {
            try execution.consumeWork(1)
            let ratio = try tryRatio(try binomial(p, i, using: &execution) * binomial(q, j, using: &execution), try binomial(p + q, i + j, using: &execution), using: &execution)
            result[i + j] = result[i + j] + left[i] * right[j] * ratio
        } }
        return result
    }

    private func binomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        if k == 0 || k == n { return 1 }
        var value = 1.0
        for index in 1...min(k, n - k) { try execution.consumeWork(1); value = value * Double(n - index + 1) / Double(index) }
        return value
    }

    private func tryRatio(_ numerator: Double, _ denominator: Double, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try execution.consumeWork(1)
        // Degrees <=22 have exact integer binomials/products (<2^53); division is outward.
        let value = numerator / denominator
        return OutwardScalarInterval(lower: value.nextDown, upper: value.nextUp)
    }

    private func elevate(_ values: Polynomial, to degree: Int, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        var result = values
        while result.count <= degree {
            let n = result.count
            try OriginalCoefficientAllocation.reserve(count: n + 1, of: OutwardScalarInterval.self, using: &execution)
            var next = Array(repeating: OutwardScalarInterval.exact(0), count: n + 1)
            next[0] = result[0]; next[n] = result[n - 1]
            if n > 1 { for index in 1..<n {
                let a = try tryRatio(Double(index), Double(n), using: &execution)
                let b = try tryRatio(Double(n - index), Double(n), using: &execution)
                next[index] = a * result[index - 1] + b * result[index]
            } }
            result = next
        }
        return result
    }

    private func add(_ left: Polynomial, _ right: Polynomial, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        let degree = max(left.count, right.count) - 1
        try OriginalCoefficientAllocation.reserve(count: degree + 1, of: OutwardScalarInterval.self, using: &execution)
        return zip(try elevate(left, to: degree, using: &execution), try elevate(right, to: degree, using: &execution)).map { $0 + $1 }
    }
    private func subtract(_ left: Polynomial, _ right: Polynomial, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        let degree = max(left.count, right.count) - 1
        try OriginalCoefficientAllocation.reserve(count: degree + 1, of: OutwardScalarInterval.self, using: &execution)
        return zip(try elevate(left, to: degree, using: &execution), try elevate(right, to: degree, using: &execution)).map { $0 - $1 }
    }
    private func scale(_ value: Polynomial, _ factor: OutwardScalarInterval, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: value.count, of: OutwardScalarInterval.self, using: &execution)
        return value.map { $0 * factor }
    }
    private func divide(_ value: Polynomial, by denominator: OutwardScalarInterval,
                        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Polynomial {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: value.count, of: OutwardScalarInterval.self, using: &execution)
        return try value.map { try quotient($0, by: denominator, tolerance: tolerance, using: &execution) }
    }
    private func quotient(_ value: OutwardScalarInterval, by denominator: OutwardScalarInterval,
                          tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try execution.consumeWork(1)
        guard let result = value.divided(by: denominator), result.isFinite else {
            throw OriginalCorrespondencePolicy.failure(.resourceLimitExceeded, tolerance,
                "Original homogeneous division has no finite nonzero interval denominator.")
        }
        return result
    }
    private func hull(_ value: Polynomial, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try execution.consumeWork(1)
        return value.dropFirst().reduce(value[0]) { $0.union($1) }
    }
    private func positiveHull(_ value: Polynomial, using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval? {
        try execution.consumeWork(1)
        let result = try hull(value, using: &execution)
        return result.isFinite && result.lower > 0 ? result : nil
    }
    private func exhausted(_ policy: OriginalCorrespondencePolicy) -> KernelError {
        OriginalCorrespondencePolicy.failure(.resourceLimitExceeded, policy.tolerance,
            "Original homogeneous correspondence exhausted bounded numeric construction.")
    }
}
