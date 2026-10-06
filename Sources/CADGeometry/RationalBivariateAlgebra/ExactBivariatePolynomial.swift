import CADCore

/// Canonical sparse polynomial over exact original rational coefficients.
public struct ExactBivariatePolynomial: Equatable, Sendable {
    public struct Power: Hashable, Sendable {
        public let u: Int
        public let v: Int
        public init(u: Int, v: Int) throws {
            guard u >= 0, v >= 0 else { throw rationalAlgebraFailure("Negative original polynomial power.") }
            self.u = u; self.v = v
        }
    }
    package var originalCoefficients: [Power: ExactRationalCoefficient] { coefficients }
    let coefficients: [Power: ExactRationalCoefficient]
    init(_ canonical: [Power: ExactRationalCoefficient]) { coefficients = canonical }
    public static let zero = Self([:])
    public var isZero: Bool { coefficients.isEmpty }
    public var uDegree: Int { coefficients.keys.reduce(-1) { max($0, $1.u) } }
    public var vDegree: Int { coefficients.keys.reduce(-1) { max($0, $1.v) } }
    var leading: (key: Power, value: ExactRationalCoefficient)? {
        coefficients.max { a, b in a.key.v == b.key.v ? a.key.u < b.key.u : a.key.v < b.key.v }
    }
    /// Returns an original constant law without materializing or evaluating a term list.
    package func originalConstantCoefficient<B: RationalAlgebraAdmitting>(usage: inout B) throws -> ExactRationalCoefficient? {
        try usage.consumeExactWork(1); try Task.checkCancellation()
        if coefficients.isEmpty { return .zero }
        guard coefficients.count == 1 else { return nil }
        return coefficients[try Power(u: 0, v: 0)]
    }
    public static func constant<B: RationalAlgebraAdmitting>(_ value: ExactRationalCoefficient,
                                                             usage: inout B) throws -> Self {
        if value.isZero { return .zero }; try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        return try Self([Power(u: 0, v: 0): value])
    }
    public static func coordinate<B: RationalAlgebraAdmitting>(alongU: Bool, usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        return try Self([Power(u: alongU ? 1 : 0, v: alongU ? 0 : 1): .one])
    }
    public func adding<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(rationalAlgebraCount(coefficients.count, other.coefficients.count), of: (Power, ExactRationalCoefficient).self, usage: &usage)
        var output = coefficients
        for (power, value) in try other.orderedTerms(usage: &usage) {
            try usage.consumeExactWork(1)
            let sum = try (output[power] ?? .zero).adding(value, usage: &usage)
            if sum.isZero { output.removeValue(forKey: power) } else { output[power] = sum }
        }
        return Self(output)
    }
    public func scaled<B: RationalAlgebraAdmitting>(by value: ExactRationalCoefficient,
                                                   usage: inout B) throws -> Self {
        if value.isZero { return .zero }; try RationalAlgebraStorage.retain(coefficients.count, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        var output: [Power: ExactRationalCoefficient] = [:]
        for (power, coefficient) in try orderedTerms(usage: &usage) {
            output[power] = try coefficient.multiplied(by: value, usage: &usage)
        }
        return Self(output)
    }
    public func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try adding(other.scaled(by: ExactRationalCoefficient.one.negated, usage: &usage), usage: &usage)
    }
    public func multiplied<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self {
        var output: [Power: ExactRationalCoefficient] = [:]
        for (a, x) in try orderedTerms(usage: &usage) { for (b, y) in try other.orderedTerms(usage: &usage) {
            try usage.consumeExactWork(1)
            let power = try Power(u: rationalAlgebraCount(a.u, b.u), v: rationalAlgebraCount(a.v, b.v))
            let value = try (output[power] ?? .zero).adding(x.multiplied(by: y, usage: &usage), usage: &usage)
            if value.isZero { output.removeValue(forKey: power) }
            else { if output[power] == nil { try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage) }; output[power] = value }
        } }
        return Self(output)
    }
    public func differentiated<B: RationalAlgebraAdmitting>(alongU: Bool, usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(coefficients.count, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        var output: [Power: ExactRationalCoefficient] = [:]
        for (power, value) in try orderedTerms(usage: &usage) {
            let n = alongU ? power.u : power.v
            if n == 0 { continue }
            let target = try Power(u: power.u - (alongU ? 1 : 0), v: power.v - (alongU ? 0 : 1))
            output[target] = try value.multiplied(by: .natural(n, usage: &usage), usage: &usage)
        }
        return Self(output)
    }
    func coefficient<B: RationalAlgebraAdmitting>(ofV degree: Int, usage: inout B) throws -> Self {
        var output: [Power: ExactRationalCoefficient] = [:]
        for (power, value) in try orderedTerms(usage: &usage) {
            try usage.consumeExactWork(1)
            if power.v == degree { try RationalAlgebraStorage.retain(1, of: (Power, ExactRationalCoefficient).self, usage: &usage); output[try Power(u: power.u, v: 0)] = value }
        }
        return Self(output)
    }
    func shiftedV<B: RationalAlgebraAdmitting>(_ degree: Int, usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(coefficients.count, of: (Power, ExactRationalCoefficient).self, usage: &usage)
        var output: [Power: ExactRationalCoefficient] = [:]
        for (power, value) in try orderedTerms(usage: &usage) {
            output[try Power(u: power.u, v: rationalAlgebraCount(power.v, degree))] = value
        }
        return Self(output)
    }
    public func normalized<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Self {
        guard let leading else { return .zero }
        return try scaled(by: .one.divided(by: leading.value, usage: &usage), usage: &usage)
    }
}
