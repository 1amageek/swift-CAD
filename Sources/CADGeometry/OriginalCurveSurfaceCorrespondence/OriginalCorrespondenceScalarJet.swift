import CADCore

/// First derivatives are with respect to the common normalized use fraction.
struct OriginalCorrespondenceScalarJet {
    let value: OutwardScalarInterval
    let derivative: OutwardScalarInterval

    static func constant(_ value: Double) -> Self {
        Self(value: .exact(value), derivative: .exact(0))
    }
    static func + (a: Self, b: Self) -> Self {
        Self(value: add(a.value, b.value), derivative: add(a.derivative, b.derivative))
    }
    static prefix func - (a: Self) -> Self {
        Self(value: -a.value, derivative: -a.derivative)
    }
    static func - (a: Self, b: Self) -> Self { a + -b }
    static func * (a: Self, b: Self) -> Self {
        Self(value: multiply(a.value, b.value),
             derivative: add(multiply(a.derivative, b.value), multiply(a.value, b.derivative)))
    }
    func divided(by b: Self, tolerance: ModelingTolerance) throws -> Self {
        guard let value = value.divided(by: b.value),
              let derivative = Self.add(Self.multiply(self.derivative, b.value),
                -Self.multiply(self.value, b.derivative)).divided(by: Self.multiply(b.value, b.value)),
              value.isFinite, derivative.isFinite else {
            throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, tolerance,
                "Original coefficient jet division has no finite nonzero interval denominator.")
        }
        return Self(value: value, derivative: derivative)
    }
    func contained(in interval: OutwardScalarInterval, tolerance: ModelingTolerance) throws -> Self {
        guard let intersection = value.intersection(with: interval), intersection.isFinite,
              derivative.isFinite else {
            throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, tolerance,
                "Original coefficient arithmetic and independently proved containment are disjoint.")
        }
        return Self(value: intersection, derivative: derivative)
    }
    func union(_ other: Self) -> Self {
        Self(value: value.union(other.value), derivative: derivative.union(other.derivative))
    }
    // Exact zero/one identities remove arithmetic overhang, never actual geometry.
    static func add(_ a: OutwardScalarInterval, _ b: OutwardScalarInterval) -> OutwardScalarInterval {
        if a.lower == 0, a.upper == 0 { return b }
        if b.lower == 0, b.upper == 0 { return a }
        return a + b
    }
    static func multiply(_ a: OutwardScalarInterval, _ b: OutwardScalarInterval) -> OutwardScalarInterval {
        if (a.lower == 0 && a.upper == 0) || (b.lower == 0 && b.upper == 0) { return .exact(0) }
        if a.lower == 1, a.upper == 1 { return b }
        if b.lower == 1, b.upper == 1 { return a }
        return a * b
    }
}
