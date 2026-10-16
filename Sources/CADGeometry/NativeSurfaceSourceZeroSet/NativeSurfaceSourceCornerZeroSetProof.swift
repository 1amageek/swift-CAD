import CADCore

/// Original coordinate zero equivalence on one retained closed Native chart.
package final class NativeSurfaceSourceCornerZeroSetProof: Sendable {
    private let originalChart: NativeSurfaceSurfaceSourceChart
    package let equationIndex: Int
    package let targetRole: Int
    package let orientation: Int
    package let zeroCorner: Int
    package let counterpartCoordinate: ExactRationalCoefficient
    package let numerator: ExactBivariatePolynomial
    package let orientedNumerator: ExactBivariatePolynomial
    package let counterpartIdentity: ExactBivariatePolynomial
    package let reconstruction: ExactBivariatePolynomial
    package let nativeBounds: [ExactRationalCoefficient]
    package let basis: [ExactBivariatePolynomial]
    package let cornerValues: [ExactRationalCoefficient]
    package let factors: [ExactBivariatePolynomial]
    package let consequences: [ExactIntersectionPolynomial]
    package let rawEquationIdentity: ExactIntersectionPolynomial

    private init(chart: NativeSurfaceSurfaceSourceChart, equationIndex: Int, targetRole: Int,
        orientation: Int, zeroCorner: Int, counterpartCoordinate: ExactRationalCoefficient,
        numerator: ExactBivariatePolynomial, orientedNumerator: ExactBivariatePolynomial,
        counterpartIdentity: ExactBivariatePolynomial, reconstruction: ExactBivariatePolynomial,
        nativeBounds: [ExactRationalCoefficient], basis: [ExactBivariatePolynomial],
        cornerValues: [ExactRationalCoefficient], factors: [ExactBivariatePolynomial],
        consequences: [ExactIntersectionPolynomial], rawEquationIdentity: ExactIntersectionPolynomial) {
        originalChart = chart; self.equationIndex = equationIndex; self.targetRole = targetRole
        self.orientation = orientation; self.zeroCorner = zeroCorner
        self.counterpartCoordinate = counterpartCoordinate; self.numerator = numerator
        self.orientedNumerator = orientedNumerator; self.counterpartIdentity = counterpartIdentity
        self.reconstruction = reconstruction; self.nativeBounds = nativeBounds; self.basis = basis
        self.cornerValues = cornerValues; self.factors = factors; self.consequences = consequences
        self.rawEquationIdentity = rawEquationIdentity
    }
    private struct Candidate {
        let orientation: Int
        let zeroCorner: Int
        let original: ExactBivariatePolynomial
        let reconstruction: ExactBivariatePolynomial
        let bounds: [ExactRationalCoefficient]
        let basis: [ExactBivariatePolynomial]
        let values: [ExactRationalCoefficient]
        let factors: [ExactBivariatePolynomial]
    }

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(chart: NativeSurfaceSurfaceSourceChart,
        usage: inout B) throws -> NativeSurfaceSourceCornerZeroSetProof? {
        try intersectionAlgebraStep(&usage)
        try NativeSurfaceSourceZeroSetProof.validateChart(chart, usage: &usage)
        for role in 0..<2 {
            let target = role == 0 ? chart.first : chart.second
            let counterpart = role == 0 ? chart.second : chart.first
            for axis in 0..<3 {
                try intersectionAlgebraStep(&usage)
                guard let constant = try NativeSurfaceSourceZeroSetProof.constantCoordinate(counterpart,
                    axis: axis, usage: &usage) else { continue }
                let n = try target.homogeneous[axis].subtracting(target.homogeneous[3]
                    .scaled(by: constant, usage: &usage), usage: &usage)
                if n.isZero { continue }
                guard let candidate = try corner(n, domain: target.domain, usage: &usage) else { continue }
                let opposite = (1 - role) * 2
                let originalN = try ExactIntersectionPolynomial.embedding(n, variableCount: 4,
                    uCoordinate: role * 2, vCoordinate: role * 2 + 1, usage: &usage)
                let originalW = try ExactIntersectionPolynomial.embedding(counterpart.homogeneous[3], variableCount: 4,
                    uCoordinate: opposite, vCoordinate: opposite + 1, usage: &usage)
                let identity = try originalN.multiplied(by: originalW, usage: &usage)
                    .scaled(by: role == 0 ? .one : .one.negated, usage: &usage)
                guard try identity.matches(chart.system.equations[axis], usage: &usage) else {
                    throw rationalAlgebraFailure("Native corner zero proof lost its original coordinate equation.")
                }
                let counterpartIdentity = try counterpart.homogeneous[3].scaled(by: constant, usage: &usage)
                try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
                try usage.consumeWork(2)
                let consequences = try [ExactIntersectionPolynomial.embedding(candidate.factors[0], variableCount: 4,
                    uCoordinate: role * 2, vCoordinate: role * 2 + 1, usage: &usage),
                    .embedding(candidate.factors[1], variableCount: 4, uCoordinate: role * 2,
                        vCoordinate: role * 2 + 1, usage: &usage)]
                try RationalAlgebraStorage.retainBytes(MemoryLayout<NativeSurfaceSourceCornerZeroSetProof>.stride
                    + MemoryLayout<NativeSurfaceSurfaceSourceChart>.stride + 4 * MemoryLayout<Int>.stride
                    + MemoryLayout<ExactRationalCoefficient>.stride + 4 * MemoryLayout<ExactBivariatePolynomial>.stride
                    + 5 * MemoryLayout<[Int]>.stride + MemoryLayout<ExactIntersectionPolynomial>.stride
                    + 2 * MemoryLayout<UnsafeRawPointer>.stride, usage: &usage)
                try CurrentTaskCancellationChecker().checkCancellation()
                return .init(chart: chart, equationIndex: axis, targetRole: role,
                    orientation: candidate.orientation, zeroCorner: candidate.zeroCorner,
                    counterpartCoordinate: constant, numerator: n, orientedNumerator: candidate.original,
                    counterpartIdentity: counterpartIdentity, reconstruction: candidate.reconstruction,
                    nativeBounds: candidate.bounds, basis: candidate.basis, cornerValues: candidate.values,
                    factors: candidate.factors, consequences: consequences, rawEquationIdentity: identity)
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return nil
    }

    package func validate<B: ExactScalarAdmission & ~Copyable>(chart: NativeSurfaceSurfaceSourceChart,
        usage: inout B) throws {
        try NativeSurfaceSourceZeroSetProof.validateChart(chart, usage: &usage)
        try NativeSurfaceSourceZeroSetProof.matching(originalChart.first, chart.first, usage: &usage)
        try NativeSurfaceSourceZeroSetProof.matching(originalChart.second, chart.second, usage: &usage)
        for axis in 0..<4 {
            guard let a = originalChart.nativeDomains[axis].lower, let b = originalChart.nativeDomains[axis].upper,
                let c = chart.nativeDomains[axis].lower, let d = chart.nativeDomains[axis].upper,
                try a.subtracting(c, usage: &usage).isZero, try b.subtracting(d, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Native corner zero proof has foreign native domains.")
            }
        }
        for axis in 0..<3 {
            guard try originalChart.system.equations[axis].matches(chart.system.equations[axis], usage: &usage) else {
                throw rationalAlgebraFailure("Native corner zero proof has a foreign original equation.")
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    private static func corner<B: ExactScalarAdmission & ~Copyable>(_ n: ExactBivariatePolynomial,
        domain: SurfaceParameterBox, usage: inout B) throws -> Candidate? {
        try RationalAlgebraStorage.retain(4, of: ExactRationalCoefficient.self, usage: &usage)
        try usage.consumeWork(4)
        let bounds = try [ExactRationalCoefficient.originalDouble(domain.u.lower, usage: &usage),
            .originalDouble(domain.u.upper, usage: &usage), .originalDouble(domain.v.lower, usage: &usage),
            .originalDouble(domain.v.upper, usage: &usage)]
        let widthU = try bounds[1].subtracting(bounds[0], usage: &usage)
        let widthV = try bounds[3].subtracting(bounds[2], usage: &usage)
        guard widthU.isPositive, widthV.isPositive else { return nil }
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let a = try u.subtracting(.constant(bounds[0], usage: &usage), usage: &usage)
            .scaled(by: .one.divided(by: widthU, usage: &usage), usage: &usage)
        let b = try v.subtracting(.constant(bounds[2], usage: &usage), usage: &usage)
            .scaled(by: .one.divided(by: widthV, usage: &usage), usage: &usage)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        let left = try one.subtracting(a, usage: &usage), lower = try one.subtracting(b, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
        try usage.consumeWork(4)
        let basis = try [left.multiplied(by: lower, usage: &usage), a.multiplied(by: lower, usage: &usage),
            left.multiplied(by: b, usage: &usage), a.multiplied(by: b, usage: &usage)]
        try RationalAlgebraStorage.retain(4, of: ExactRationalCoefficient.self, usage: &usage)
        var values: [ExactRationalCoefficient] = []; values.reserveCapacity(4)
        var zeroCorner: Int?, orientation = 0
        for corner in 0..<4 {
            try intersectionAlgebraStep(&usage)
            let value = try n.evaluated(atU: bounds[corner % 2], v: bounds[2 + corner / 2], usage: &usage)
            if value.isZero {
                if zeroCorner != nil { return nil }
                zeroCorner = corner
            } else if orientation == 0 { orientation = value.canonicalSign }
            else if value.canonicalSign != orientation { return nil }
            values.append(value)
        }
        guard let zeroCorner, orientation != 0 else { return nil }
        var reconstruction = ExactBivariatePolynomial.zero
        for corner in 0..<4 {
            try intersectionAlgebraStep(&usage)
            if orientation < 0 { values[corner] = values[corner].negated }
            reconstruction = try reconstruction.adding(basis[corner].scaled(by: values[corner], usage: &usage), usage: &usage)
        }
        let original = try n.scaled(by: orientation > 0 ? .one : .one.negated, usage: &usage)
        guard try original.subtracting(reconstruction, usage: &usage).isZero else { return nil }
        try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
        try usage.consumeWork(2)
        let factors = try [u.subtracting(.constant(bounds[zeroCorner % 2], usage: &usage), usage: &usage),
            v.subtracting(.constant(bounds[2 + zeroCorner / 2], usage: &usage), usage: &usage)]
        return .init(orientation: orientation, zeroCorner: zeroCorner, original: original,
            reconstruction: reconstruction, bounds: bounds, basis: basis, values: values, factors: factors)
    }
}
