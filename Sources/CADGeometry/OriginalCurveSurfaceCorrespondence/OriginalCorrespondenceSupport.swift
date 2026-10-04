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

    init(surface: Surface3D, budget: inout OriginalCorrespondenceBudget) throws {
        switch surface {
        case let .plane(value):
            let n = value.normal
            guard (abs(n.x) == 1 && n.y == 0 && n.z == 0)
                || (abs(n.y) == 1 && n.x == 0 && n.z == 0)
                || (abs(n.z) == 1 && n.x == 0 && n.y == 0) else { throw budget.unsupported() }
            try value.validate(tolerance: budget.tolerance)
            let basis = try value.parameterBasis(tolerance: budget.tolerance)
            plane = value; basisU = basis.u; basisV = basis.v
            spline = nil; uSpans = []; uDomain = nil; vDomain = nil
        case let .bSpline(value):
            // Main-native BSplineSurface3D has no cyclic metadata; exact
            // closed-domain validation and the clamped/multiplicity checks below
            // are the nonperiodic support admission authority.
            guard value.uDegree == 3,
                  value.vDegree == 1, value.vControlPointCount == 2 else { throw budget.unsupported() }
            try value.validate(tolerance: budget.tolerance)
            let u0 = value.uKnots[3], u1 = value.uKnots[value.uControlPointCount]
            let v0 = value.vKnots[1], v1 = value.vKnots[2]
            guard value.uKnots.prefix(4).allSatisfy({ $0 == u0 }),
                  value.uKnots.suffix(4).allSatisfy({ $0 == u1 }),
                  value.vKnots == [v0, v0, v1, v1] else { throw budget.unsupported() }
            var index = 4
            while index < value.uControlPointCount {
                var end = index + 1
                while end < value.uControlPointCount, value.uKnots[end] == value.uKnots[index] { end += 1 }
                guard end - index <= 3 else { throw budget.unsupported() }
                index = end
            }
            var records: [Int] = []
            for index in 3..<value.uControlPointCount where value.uKnots[index] < value.uKnots[index + 1] {
                try budget.charge(); records.append(index)
            }
            spline = value; uSpans = records
            plane = nil; basisU = nil; basisV = nil
            uDomain = OutwardScalarInterval(lower: u0, upper: u1)
            vDomain = OutwardScalarInterval(lower: v0, upper: v1)
        default: throw budget.unsupported()
        }
    }

    func enclose(u: OriginalCorrespondenceScalarJet, v: OriginalCorrespondenceScalarJet,
                 budget: inout OriginalCorrespondenceBudget) throws -> [OriginalCorrespondenceScalarJet] {
        if let plane, let basisU, let basisV {
            try budget.charge()
            return [
                .constant(plane.origin.x) + .constant(basisU.x) * u + .constant(basisV.x) * v,
                .constant(plane.origin.y) + .constant(basisU.y) * u + .constant(basisV.y) * v,
                .constant(plane.origin.z) + .constant(basisU.z) * u + .constant(basisV.z) * v]
        }
        guard let spline, let uDomain, let vDomain else {
            throw OriginalCorrespondenceBudget.failure(.invalidInput, budget.tolerance, "Missing original support.")
        }
        // Global original pcurve/control containment was independently proved at admission.
        let u = try u.contained(in: uDomain, tolerance: budget.tolerance)
        let v = try v.contained(in: vDomain, tolerance: budget.tolerance)
        let vb = try Self.basis(parameter: v, degree: 1, span: 1,
            knots: spline.vKnots, tolerance: budget.tolerance)
        var first = 0, last = uSpans.count
        while first < last {
            let mid = first + (last - first) / 2
            if spline.uKnots[uSpans[mid] + 1] < u.value.lower { first = mid + 1 } else { last = mid }
        }
        var result: [OriginalCorrespondenceScalarJet]?
        var index = first
        while index < uSpans.count, spline.uKnots[uSpans[index]] <= u.value.upper {
            try budget.charge()
            let span = uSpans[index]
            let q = try u.contained(in: OutwardScalarInterval(lower: spline.uKnots[span],
                upper: spline.uKnots[span + 1]), tolerance: budget.tolerance)
            let ub = try Self.basis(parameter: q, degree: 3, span: span,
                knots: spline.uKnots, tolerance: budget.tolerance)
            let values = try homogeneous(spline, uBasis: ub, vBasis: vb, firstControl: span - 3,
                tolerance: budget.tolerance)
            if let old = result { result = zip(old, values).map { $0.union($1) } } else { result = values }
            index += 1
        }
        guard let result else {
            throw OriginalCorrespondenceBudget.failure(.invalidInput, budget.tolerance,
                "No original surface span contains the parameter image.")
        }
        return result
    }

    private static func basis(parameter: OriginalCorrespondenceScalarJet, degree: Int,
                              span: Int, knots: [Double], tolerance: ModelingTolerance) throws
        -> [OriginalCorrespondenceScalarJet] {
        var values = Array(repeating: OriginalCorrespondenceScalarJet.constant(0), count: degree + 1)
        values[0] = .constant(1)
        for order in 1...degree {
            var saved = OriginalCorrespondenceScalarJet.constant(0)
            for row in 0..<order {
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
                             tolerance: ModelingTolerance) throws -> [OriginalCorrespondenceScalarJet] {
        var weight = OriginalCorrespondenceScalarJet.constant(0)
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
