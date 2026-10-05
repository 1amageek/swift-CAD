/// Conservative original-expression identity for transient immutable receipts.
package enum OriginalSingularFieldIdentity {
    package static func same(_ a: OriginalSingularFieldPlanePolynomial,
        _ b: OriginalSingularFieldPlanePolynomial) -> Bool {
        guard a.context === b.context, a.coefficients.count == b.coefficients.count else { return false }
        for (power, value) in a.coefficients {
            guard let other = b.coefficients[power], same(value, other) else { return false }
        }
        return true
    }
    package static func same(_ a: OriginalSingularFieldElement, _ b: OriginalSingularFieldElement) -> Bool {
        guard a.context === b.context else { return false }
        switch (a.storage, b.storage) {
        case (.original(let an, let ad), .original(let bn, let bd)): return an == bn && ad == bd
        case (.extended(let an, let ad), .extended(let bn, let bd)): return same(an, bn) && same(ad, bd)
        default: return false
        }
    }
    private static func same(_ a: OriginalSingularFieldPolynomial, _ b: OriginalSingularFieldPolynomial) -> Bool {
        guard a.context === b.context, a.coefficients.count == b.coefficients.count else { return false }
        for index in a.coefficients.indices {
            if !same(a.coefficients[index], b.coefficients[index]) { return false }
        }
        return true
    }
}
