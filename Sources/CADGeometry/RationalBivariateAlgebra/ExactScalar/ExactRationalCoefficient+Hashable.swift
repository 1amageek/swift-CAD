extension ExactRationalCoefficient: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(canonicalSign)
        hasher.combine(canonicalNumeratorWords)
        hasher.combine(canonicalDenominatorWords)
    }
}
