import CADCore

/// Original curve labels and exact directed construction fractions.
public struct OriginalCurveConstructionParameterSource: Hashable, Sendable {
    public let source: Curve3D
    public let startParameter: Double
    public let endParameter: Double
    public let law: OriginalCurveConstructionParameterLaw
    public let firstFraction: ExactRationalCoefficient
    public let lastFraction: ExactRationalCoefficient

    public init(source: Curve3D, startParameter: Double, endParameter: Double,
        law: OriginalCurveConstructionParameterLaw, firstFraction: ExactRationalCoefficient,
        lastFraction: ExactRationalCoefficient) {
        self.source = source; self.startParameter = startParameter; self.endParameter = endParameter
        self.law = law; self.firstFraction = firstFraction; self.lastFraction = lastFraction
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.source == b.source && a.startParameter == b.startParameter && a.endParameter == b.endParameter
            && a.law == b.law && a.firstFraction == b.firstFraction && a.lastFraction == b.lastFraction
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(source); hasher.combine(startParameter); hasher.combine(endParameter); hasher.combine(law)
        for value in [firstFraction, lastFraction] {
            hasher.combine(value.canonicalSign); hasher.combine(value.canonicalNumeratorWords)
            hasher.combine(value.canonicalDenominatorWords)
        }
    }
}
