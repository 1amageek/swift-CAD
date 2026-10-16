import CADCore

/// The raw normalized-direction geometry law, independent of foreign record identity.
public struct OriginalNormalizedAffineSource: Hashable, Sendable {
    public enum Family: String, Hashable, Sendable { case axis2, cartesian }
    public let family: Family
    public let location: Vector3D
    public let axis1: Vector3D?
    public let axis2: Vector3D?
    public let axis3: Vector3D?
    public let scale: Double?
    public let lengthGain: ExactRationalCoefficient
    public let linearGain: ExactRationalCoefficient
    public let adjustments: [OriginalNormalizedAffineAdjustment]

    public init(family: Family, location: Vector3D, axis1: Vector3D?, axis2: Vector3D?,
        axis3: Vector3D?, scale: Double?, lengthGain: ExactRationalCoefficient,
        linearGain: ExactRationalCoefficient = .one, adjustments: [OriginalNormalizedAffineAdjustment]) {
        self.family = family; self.location = location; self.axis1 = axis1
        self.axis2 = axis2; self.axis3 = axis3; self.scale = scale
        self.lengthGain = lengthGain; self.adjustments = adjustments; self.linearGain = linearGain
    }
    func prepared<B: ExactScalarAdmission & ~Copyable>(in context: OriginalSingularFieldContext,
        tolerance: ModelingTolerance, maximumDepth: Int, usage: inout B) throws -> OriginalRationalNormalizedFrame {
        if family == .axis2, axis2 != nil || scale != nil {
            throw rationalAlgebraFailure("An original axis placement cannot contain Cartesian scale or second-axis fields.")
        }
        try usage.consumeWork(adjustments.count)
        try OriginalAffineRationalMatrix.retain(adjustments.count,
            of: (displacement: Vector3D, conjugates: Bool).self, usage: &usage)
        var retained: [(displacement: Vector3D, conjugates: Bool)] = []
        retained.reserveCapacity(adjustments.count)
        for adjustment in adjustments { retained.append((adjustment.displacement, adjustment.conjugates)) }
        return try OriginalRationalNormalizedFrame(family: family == .axis2 ? .axis2 : .cartesian,
            location: location, axis1: axis1, axis2: axis2, axis3: axis3, scale: scale,
            lengthGain: lengthGain, linearGain: linearGain, adjustments: retained, in: context, tolerance: tolerance,
            normalizationPolicy: .dimensionlessOriginalDirections, inheritedDepth: context.depth, maximumDepth: maximumDepth, usage: &usage)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(family); hasher.combine(location); hasher.combine(axis1)
        hasher.combine(axis2); hasher.combine(axis3); hasher.combine(scale)
        hasher.combine(lengthGain.canonicalSign)
        hasher.combine(lengthGain.canonicalNumeratorWords)
        hasher.combine(lengthGain.canonicalDenominatorWords)
        hasher.combine(linearGain.canonicalSign)
        hasher.combine(linearGain.canonicalNumeratorWords)
        hasher.combine(linearGain.canonicalDenominatorWords)
        hasher.combine(adjustments)
    }
}
