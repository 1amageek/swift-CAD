import CADCore

/// Original spline basis evaluation on every closed owning native span.
struct OriginalCorrespondenceSupport {
    private let plane: Plane3D?
    private let basisU: Vector3D?
    private let basisV: Vector3D?
    private let spline: BSplineSurface3D?
    private let uSpans: [Int]
    let uDomain: OutwardScalarInterval?
    let vDomain: OutwardScalarInterval?

    init(surface: Surface3D, policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws {
        switch surface {
        case let .plane(value):
            let n = value.normal
            guard (abs(n.x) == 1 && n.y == 0 && n.z == 0)
                || (abs(n.y) == 1 && n.x == 0 && n.z == 0)
                || (abs(n.z) == 1 && n.x == 0 && n.y == 0) else { throw policy.unsupported() }
            try execution.consumeWork(1); try value.validate(tolerance: policy.tolerance)
            let basis = try value.parameterBasis(tolerance: policy.tolerance)
            plane = value; basisU = basis.u; basisV = basis.v
            spline = nil; uSpans = []; uDomain = nil; vDomain = nil
        case let .bSpline(value):
            guard !value.isUPeriodic, !value.isVPeriodic, value.uDegree == 3,
                  value.vDegree == 1, value.vControlPointCount == 2 else { throw policy.unsupported() }
            try value.validate(tolerance: policy.tolerance, using: &execution)
            let u0 = value.uKnots[3], u1 = value.uKnots[value.uControlPointCount]
            let v0 = value.vKnots[1], v1 = value.vKnots[2]
            guard value.uKnots.prefix(4).allSatisfy({ $0 == u0 }),
                  value.uKnots.suffix(4).allSatisfy({ $0 == u1 }),
                  value.vKnots == [v0, v0, v1, v1] else { throw policy.unsupported() }
            var index = 4
            while index < value.uControlPointCount {
                var end = index + 1
                while end < value.uControlPointCount, value.uKnots[end] == value.uKnots[index] { end += 1 }
                guard end - index <= 3 else { throw policy.unsupported() }
                index = end
            }
            let capacity = value.uControlPointCount - 3
            try OriginalCoefficientAllocation.reserve(count: capacity, of: Int.self, using: &execution)
            var records: [Int] = []
            records.reserveCapacity(capacity)
            for index in 3..<value.uControlPointCount where value.uKnots[index] < value.uKnots[index + 1] {
                try policy.charge(using: &execution); records.append(index)
            }
            spline = value; uSpans = records
            plane = nil; basisU = nil; basisV = nil
            uDomain = OutwardScalarInterval(lower: u0, upper: u1)
            vDomain = OutwardScalarInterval(lower: v0, upper: v1)
        default: throw policy.unsupported()
        }
    }

    func enclose(u: OriginalCorrespondenceScalarJet, v: OriginalCorrespondenceScalarJet,
                 policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws -> [OriginalCorrespondenceScalarJet] {
        if let plane, let basisU, let basisV {
            try policy.charge(using: &execution)
            try OriginalCoefficientAllocation.reserve(count: 3, of: OriginalCorrespondenceScalarJet.self, using: &execution)
            return [
                .constant(plane.origin.x) + .constant(basisU.x) * u + .constant(basisV.x) * v,
                .constant(plane.origin.y) + .constant(basisU.y) * u + .constant(basisV.y) * v,
                .constant(plane.origin.z) + .constant(basisU.z) * u + .constant(basisV.z) * v]
        }
        guard let spline, let uDomain, let vDomain else {
            throw OriginalCorrespondencePolicy.failure(.invalidInput, policy.tolerance, "Missing original support.")
        }
        // Global original pcurve/control containment was independently proved at admission.
        let u = try u.contained(in: uDomain, tolerance: policy.tolerance)
        let v = try v.contained(in: vDomain, tolerance: policy.tolerance)
        let vb = try Self.basis(parameter: v, degree: 1, span: 1,
            knots: spline.vKnots, tolerance: policy.tolerance, using: &execution)
        var first = 0, last = uSpans.count
        while first < last {
            let mid = first + (last - first) / 2
            if spline.uKnots[uSpans[mid] + 1] < u.value.lower { first = mid + 1 } else { last = mid }
        }
        var result: [OriginalCorrespondenceScalarJet]?
        var index = first
        while index < uSpans.count, spline.uKnots[uSpans[index]] <= u.value.upper {
            try policy.charge(using: &execution)
            let span = uSpans[index]
            let q = try u.contained(in: OutwardScalarInterval(lower: spline.uKnots[span],
                upper: spline.uKnots[span + 1]), tolerance: policy.tolerance)
            let ub = try Self.basis(parameter: q, degree: 3, span: span,
                knots: spline.uKnots, tolerance: policy.tolerance, using: &execution)
            let values = try homogeneous(spline, uBasis: ub, vBasis: vb, firstControl: span - 3,
                tolerance: policy.tolerance, using: &execution)
            if let old = result { try OriginalCoefficientAllocation.reserve(count: old.count, of: OriginalCorrespondenceScalarJet.self, using: &execution); result = zip(old, values).map { $0.union($1) } } else { result = values }
            index += 1
        }
        guard let result else {
            throw OriginalCorrespondencePolicy.failure(.invalidInput, policy.tolerance,
                "No original surface span contains the parameter image.")
        }
        return result
    }

    private static func basis(parameter: OriginalCorrespondenceScalarJet, degree: Int,
                              span: Int, knots: [Double], tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws
        -> [OriginalCorrespondenceScalarJet] {
        try OriginalCoefficientAllocation.reserve(count: degree + 1, of: OriginalCorrespondenceScalarJet.self, using: &execution)
        var values = Array(repeating: OriginalCorrespondenceScalarJet.constant(0), count: degree + 1)
        values[0] = .constant(1)
        for order in 1...degree {
            var saved = OriginalCorrespondenceScalarJet.constant(0)
            for row in 0..<order {
                try execution.consumeWork(1)
                let lowKnot = knots[span + 1 - order + row]
                let highKnot = knots[span + row + 1]
                // Use the original knot difference; do not lose dependency in (k-u)+(u-k).
                let denominator = OriginalCorrespondenceScalarJet.constant(highKnot) - .constant(lowKnot)
                let term = try values[row].divided(by: denominator, tolerance: tolerance)
                let left = parameter - .constant(lowKnot)
                let right = OriginalCorrespondenceScalarJet.constant(highKnot) - parameter
                values[row] = saved + right * term
                saved = left * term
            }
            values[order] = saved
            // Cox basis on the independently selected closed native span is nonnegative and <=1.
            for row in 0...order {
                values[row] = try values[row].contained(in: OutwardScalarInterval(lower: 0, upper: 1),
                    tolerance: tolerance)
            }
        }
        return values
    }

    private func homogeneous(_ surface: BSplineSurface3D,
                             uBasis: [OriginalCorrespondenceScalarJet],
                             vBasis: [OriginalCorrespondenceScalarJet], firstControl: Int,
                             tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [OriginalCorrespondenceScalarJet] {
        var weight = OriginalCorrespondenceScalarJet.constant(0)
        try OriginalCoefficientAllocation.reserve(count: 3, of: OriginalCorrespondenceScalarJet.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 6, of: Double.self, using: &execution)
        var coordinates = Array(repeating: OriginalCorrespondenceScalarJet.constant(0), count: 3)
        var low = [Double.infinity, Double.infinity, Double.infinity]
        var high = [-Double.infinity, -Double.infinity, -Double.infinity]
        var w0 = Double.infinity, w1 = -Double.infinity
        for row in 0..<2 { for column in 0..<4 {
            let index = firstControl + column
            let point = surface.controlPoints[row][index]
            let w = surface.weights[row][index]
            let factor = vBasis[row] * uBasis[column] * .constant(w)
            weight = weight + factor
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count: 3, of: Double.self, using: &execution)
            let components = [point.x, point.y, point.z]
            for axis in 0..<3 {
                coordinates[axis] = coordinates[axis] + factor * .constant(components[axis])
                low[axis] = min(low[axis], components[axis]); high[axis] = max(high[axis], components[axis])
            }
            w0 = min(w0, w); w1 = max(w1, w)
        } }
        weight = w0 == w1 ? .constant(w0)
            : try weight.contained(in: OutwardScalarInterval(lower: w0, upper: w1), tolerance: tolerance)
        for axis in 0..<3 {
            coordinates[axis] = low[axis] == high[axis] ? .constant(low[axis])
                : try coordinates[axis].divided(by: weight, tolerance: tolerance)
                    .contained(in: OutwardScalarInterval(lower: low[axis], upper: high[axis]), tolerance: tolerance)
        }
        return coordinates
    }
}
