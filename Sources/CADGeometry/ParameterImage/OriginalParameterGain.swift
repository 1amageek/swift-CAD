import CADCore

/// A retained original signed scalar gain; a ratio is never replaced by its estimate.
public enum OriginalParameterGain: Hashable, Sendable {
    case binary(Double)
    case ratio(numerator: Double, denominator: Double)
    case product(Product)
    indirect case difference(Difference)

    /// Source factors own identity; exact derived caches are invocation-prepared.
    public struct Product: Hashable, Sendable {
        public let factors: [OriginalParameterGain]
        fileprivate let coefficient: ExactRationalCoefficient
        fileprivate let bounds: OutwardScalarInterval
        fileprivate init(factors: [OriginalParameterGain], coefficient: ExactRationalCoefficient,
          bounds: OutwardScalarInterval) {
            self.factors = factors; self.coefficient = coefficient; self.bounds = bounds
        }
        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.factors == rhs.factors }
        public func hash(into hasher: inout Hasher) { hasher.combine(factors) }
    }

    /// Original directed endpoints, with only immutable derived arithmetic caches.
    public struct Difference: Hashable, Sendable {
        public let originalLower: Double
        public let originalUpper: Double
        public let periodicTranslation: OriginalParameterPeriodicTranslation
        fileprivate let coefficient: ExactRationalCoefficient
        fileprivate let bounds: OutwardScalarInterval
        fileprivate init(originalLower: Double, originalUpper: Double,
            periodicTranslation: OriginalParameterPeriodicTranslation,
            coefficient: ExactRationalCoefficient, bounds: OutwardScalarInterval) {
            self.originalLower = originalLower; self.originalUpper = originalUpper
            self.periodicTranslation = periodicTranslation
            self.coefficient = coefficient; self.bounds = bounds
        }
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.originalLower == rhs.originalLower && lhs.originalUpper == rhs.originalUpper
                && lhs.periodicTranslation == rhs.periodicTranslation
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(originalLower); hasher.combine(originalUpper)
            hasher.combine(periodicTranslation)
        }
    }

    public static func originalDifference<B: ExactScalarAdmission & ~Copyable>(originalLower: Double,
        originalUpper: Double, periodicTranslation: OriginalParameterPeriodicTranslation,
        usage: inout B) throws -> Self {
        try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitCell(axis: .value, depth: 0)
        try periodicTranslation.validate()
        let coefficient = try ExactRationalCoefficient.originalDouble(originalUpper, usage: &usage)
            .subtracting(.originalDouble(originalLower, usage: &usage), usage: &usage)
            .adding(periodicTranslation.foreignDisplacement(usage: &usage), usage: &usage)
        let bounds = try coefficient.outwardInterval(usage: &usage)
        guard bounds.isFinite, bounds.excludesZero else {
            throw GeometryConversionError.resourceLimitExceeded("Original directed chart has no finite nonzero signed gain enclosure.")
        }
        return .difference(.init(originalLower: originalLower, originalUpper: originalUpper,
            periodicTranslation: periodicTranslation, coefficient: coefficient, bounds: bounds))
    }

    public static func originalProduct<B: ExactScalarAdmission & ~Copyable>(
        factors: [OriginalParameterGain], usage: inout B) throws -> Self {
        guard !factors.isEmpty else {
            throw GeometryConversionError.invalidInput("An original gain product needs retained source factors.")
        }
        try usage.visitCell(axis: .value, depth: 0)
        var originals: [OriginalParameterGain] = []
        var coefficient = ExactRationalCoefficient.one
        for factor in factors {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeWork(1); try factor.validate()
            let next: [OriginalParameterGain]
            if case .product(let product) = factor { next = product.factors } else { next = [factor] }
            try usage.retainStorage(bytes: exactScalarPayloadBytes(count: next.count, of: UInt32.self))
            for original in next {
                try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeWork(1)
                coefficient = try coefficient.multiplied(by: original.exactCoefficient(usage: &usage), usage: &usage)
                originals.append(original)
            }
        }
        let bounds = try coefficient.outwardInterval(usage: &usage)
        guard bounds.isFinite, bounds.excludesZero else {
            throw GeometryConversionError.resourceLimitExceeded("Original factor product has no finite nonzero binary enclosure.")
        }
        return .product(.init(factors: originals, coefficient: coefficient, bounds: bounds))
    }

    public func exactCoefficient<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> ExactRationalCoefficient {
        try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeWork(1)
        switch self {
        case .binary(let value): return try .originalDouble(value, usage: &usage)
        case .ratio(let numerator, let denominator):
            return try ExactRationalCoefficient.originalDouble(numerator, usage: &usage)
                .divided(by: .originalDouble(denominator, usage: &usage), usage: &usage)
        case .product(let original): return original.coefficient
        case .difference(let original): return original.coefficient
        }
    }

    public func applied<B: ExactScalarAdmission & ~Copyable>(to value: Double, usage: inout B) throws -> Double {
        let result = try exactCoefficient(usage: &usage)
            .multiplied(by: .originalDouble(value, usage: &usage), usage: &usage)
            .outwardInterval(usage: &usage)
        guard result.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Original gain evaluation exceeds finite arithmetic.") }
        return result.midpoint
    }

    public func inverseApplied<B: ExactScalarAdmission & ~Copyable>(to value: Double, usage: inout B) throws -> Double {
        let result = try ExactRationalCoefficient.originalDouble(value, usage: &usage)
            .divided(by: exactCoefficient(usage: &usage), usage: &usage).outwardInterval(usage: &usage)
        guard result.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Original inverse gain evaluation exceeds finite arithmetic.") }
        return result.midpoint
    }

    public func isEquivalent<B: ExactScalarAdmission & ~Copyable>(to other: Self, usage: inout B) throws -> Bool {
        try exactCoefficient(usage: &usage) == other.exactCoefficient(usage: &usage)
    }

    public var value: Double {
        switch self {
        case .binary(let value): value
        case .ratio(let numerator, let denominator): numerator / denominator
        case .product(let original): original.bounds.midpoint
        case .difference(let original): original.bounds.midpoint
        }
    }

    public func validate() throws {
        if case .product(let original) = self {
            guard !original.factors.isEmpty, original.bounds.isFinite, original.bounds.excludesZero else {
                throw GeometryConversionError.invalidInput("Original product gain lost its immutable source preparation.")
            }
            return
        }
        if case .difference(let original) = self {
            guard original.originalLower.isFinite, original.originalUpper.isFinite,
                original.bounds.isFinite, original.bounds.excludesZero else {
                throw GeometryConversionError.invalidInput("Original difference gain lost its immutable source preparation.")
            }
            return
        }
        let pair = coefficients
        guard pair.numerator.isFinite, pair.numerator != 0,
              pair.denominator.isFinite, pair.denominator != 0,
              value.isFinite, value != 0 else {
            throw GeometryConversionError.invalidInput("An original parameter gain requires a finite nonzero ratio.")
        }
    }

    /// Numeric evaluation pair only. Product source proofs use exactCoefficient
    /// or every retained factor; this pair never supplies exact product authority.
    var coefficients: (numerator: Double, denominator: Double) {
        switch self {
        case .binary(let value): (value, 1)
        case .ratio(let numerator, let denominator):
            denominator < 0 ? (-numerator, -denominator) : (numerator, denominator)
        case .product(let original): (original.bounds.midpoint, 1)
        case .difference(let original): (original.bounds.midpoint, 1)
        }
    }

    func interval() throws -> OutwardScalarInterval {
        try validate()
        if case .product(let original) = self { return original.bounds }
        if case .difference(let original) = self { return original.bounds }
        let pair = coefficients
        guard let result = OutwardScalarInterval.exact(pair.numerator)
            .divided(by: .exact(pair.denominator)), result.isFinite else {
            throw GeometryConversionError.invalidInput("Original parameter gain interval is nonfinite.")
        }
        return result
    }

}

#if !hasFeature(Embedded)
extension OriginalParameterGain: Codable {
    private enum CodingKeys: String, CodingKey { case kind, binary, numerator, denominator, factors, originalLower, originalUpper, periodicTranslation }
    private enum Kind: String, Codable { case binary, ratio, product, difference }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .binary:
            try container.validateOnlyExpectedKeys([.kind, .binary], in: decoder)
            self = .binary(try container.decode(Double.self, forKey: .binary))
        case .ratio:
            try container.validateOnlyExpectedKeys([.kind, .numerator, .denominator], in: decoder)
            self = .ratio(numerator: try container.decode(Double.self, forKey: .numerator),
                denominator: try container.decode(Double.self, forKey: .denominator))
        case .difference:
            var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            try usage.visitCell(axis: .value, depth: 0)
            try container.validateOnlyExpectedKeys([.kind, .originalLower, .originalUpper, .periodicTranslation], in: decoder)
            let lower = try container.decode(Double.self, forKey: .originalLower)
            let upper = try container.decode(Double.self, forKey: .originalUpper)
            let translation = try container.decode(OriginalParameterPeriodicTranslation.self, forKey: .periodicTranslation)
            self = try .originalDifference(originalLower: lower, originalUpper: upper,
                periodicTranslation: translation, usage: &usage)
        case .product:
            var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            try container.validateOnlyExpectedKeys([.kind, .factors], in: decoder)
            var source = try container.nestedUnkeyedContainer(forKey: .factors)
            guard let count = source.count else { throw NativeRationalSourceDecodingError.unboundedWordContainer }
            try usage.consumeWork(count); try usage.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: UInt32.self))
            var factors: [OriginalParameterGain] = []; factors.reserveCapacity(count)
            while !source.isAtEnd {
                try usage.visitCell(axis: .value, depth: 0)
                let originalDecoder = try source.superDecoder()
                try OriginalAffineWordDecodingContext.validateSourceNesting(from: originalDecoder)
                let fields = try originalDecoder.container(keyedBy: CodingKeys.self)
                guard try fields.decode(Kind.self, forKey: .kind) != .product else {
                    throw GeometryConversionError.invalidInput("Native original factor products require their flat source representation.")
                }
                factors.append(try OriginalParameterGain(from: originalDecoder))
            }
            self = try .originalProduct(factors: factors, usage: &usage)
        }
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .binary(let value):
            try container.encode(Kind.binary, forKey: .kind)
            try container.encode(value, forKey: .binary)
        case .ratio(let numerator, let denominator):
            try container.encode(Kind.ratio, forKey: .kind)
            try container.encode(numerator, forKey: .numerator)
            try container.encode(denominator, forKey: .denominator)
        case .difference(let original):
            try container.encode(Kind.difference, forKey: .kind)
            try container.encode(original.originalLower, forKey: .originalLower)
            try container.encode(original.originalUpper, forKey: .originalUpper)
            try container.encode(original.periodicTranslation, forKey: .periodicTranslation)
        case .product(let original):
            try container.encode(Kind.product, forKey: .kind)
            try container.encode(original.factors, forKey: .factors)
        }
    }
}
#endif
