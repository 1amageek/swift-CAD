import CADCore
import CADGeometry

extension IndependentShapeAngularSource {
    /// Nonpersistent interpretation receipt; raw unit records remain the source authority.
    public enum CoordinateLaw: Hashable, Sendable {
        case canonicalGain(OriginalParameterGain)
        case physicalRadians(ExactRationalCoefficient)
    }
    public func originalCoordinateLaw(maximumSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> CoordinateLaw {
        var current = self, degreeCount = 0, depth = 0
        while true {
            depth += 1
            guard depth <= maximumSourceDepth else { throw IndependentShapeSourceError.resourceLimitExceeded("Original angular coordinate source depth.") }
            try execution.visitCell(axis: .value, depth: 0); try execution.consumeWork(1)
            switch current.law {
            case .radian: break
            case .conversion(let conversion):
                if conversion.interpretation == .canonicalDegree { degreeCount += 1 }
                current = conversion.base; continue
            }
            break
        }
        if degreeCount == 0 {
            return .physicalRadians(try originalCoefficient(maximumSourceDepth: maximumSourceDepth, using: &execution))
        }
        return .canonicalGain(try originalParameterGain(maximumSourceDepth: maximumSourceDepth, using: &execution))
    }
    /// Produces the original coefficient product without collapsing its source factors.
    public func originalParameterGain(maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> OriginalParameterGain {
        var current = self, degreeCount = 0, depth = 0
        while true {
            depth += 1
            guard depth <= maximumSourceDepth else { throw IndependentShapeSourceError.resourceLimitExceeded("Original angular coordinate source depth.") }
            try execution.visitCell(axis: .value, depth: 0); try execution.consumeWork(1)
            switch current.law {
            case .radian: break
            case .conversion(let conversion):
                if conversion.interpretation == .canonicalDegree { degreeCount += 1 }
                current = conversion.base; continue
            }
            break
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Higher canonical-degree powers require their own retained symbolic phase producer.
        // This canonical-gain API accepts exactly one degree factor; physical-radian consumers use originalCoordinateLaw instead.
        // No rational Native gain may stand in for unimplemented higher mathematical-pi authority.
        guard degreeCount == 1 else {
            throw IndependentShapeSourceError.unprovedAngularCoordinateLaw(id)
        }
        let factors = try originalFactors(maximumSourceDepth: maximumSourceDepth, using: &execution)
        if factors.isEmpty { return .binary(1) }
        if factors.count == 1 { return factors[0] }
        return try OriginalParameterGain.originalProduct(factors: factors, usage: &execution)
    }
    /// Compares coordinate meaning without requiring a finite binary64 gain estimate.
    public func isCoordinateLawEquivalent(to other: Self, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
        let first = try originalCoordinateLaw(maximumSourceDepth: maximumSourceDepth, using: &execution)
        let second = try other.originalCoordinateLaw(maximumSourceDepth: maximumSourceDepth, using: &execution)
        switch (first, second) {
        case let (.canonicalGain(a), .canonicalGain(b)): return try a.isEquivalent(to: b, usage: &execution)
        case let (.physicalRadians(a), .physicalRadians(b)): return try a.subtracting(b, usage: &execution).isZero
        default: return false
        }
    }
    private func originalCoefficient(maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        let factors = try originalFactors(maximumSourceDepth: maximumSourceDepth, using: &execution)
        var coefficient = ExactRationalCoefficient.one
        for factor in factors {
            coefficient = try coefficient.multiplied(by: factor.exactCoefficient(usage: &execution), usage: &execution)
        }
        return coefficient
    }
    private func originalFactors(maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> [OriginalParameterGain] {
        var current = self
        var depth = 0
        var factors: [OriginalParameterGain] = []
        var visited = Set<IndependentShapeAngularUnitID>()
        while true {
            depth += 1
            guard depth <= maximumSourceDepth else { throw IndependentShapeSourceError.resourceLimitExceeded("Original angular source nesting exceeds its caller ceiling.") }
            try execution.visitCell(axis: .value, depth: 0)
            try execution.consumeWork(8)
            try RationalAlgebraStorage.retain(1, of: UInt32.self, usage: &execution)
            guard visited.insert(current.id).inserted else {
                throw IndependentShapeSourceError.invalidSource("Original angular conversion chain is cyclic.")
            }
            switch current.law {
            case .radian(let prefix):
                if let prefix {
                    let exponent = prefix.decimalExponent
                    let powers: [Double] = [1,10,100,1000,10000,100000,1000000,10000000,100000000,
                        1000000000,10000000000,100000000000,1000000000000,10000000000000,
                        100000000000000,1000000000000000,10000000000000000,100000000000000000,
                        1000000000000000000]
                    let power = powers[abs(exponent)]
                    factors.append(exponent < 0 ? .ratio(numerator: 1, denominator: power) : .binary(power))
                }
                return factors
            case .conversion(let conversion):
                guard conversion.factor.isFinite, conversion.factor > 0,
                      (conversion.factor == AngleUnit.degree.toInternal(1)) == (conversion.interpretation == .canonicalDegree) else {
                    throw IndependentShapeSourceError.invalidSource("Original angular factor and interpretation disagree.")
                }
                factors.append(conversion.interpretation == .canonicalDegree
                    ? .ratio(numerator: Double.pi, denominator: 180) : .binary(conversion.factor))
                current = conversion.base
            }
        }
    }
}
