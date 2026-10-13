import CADCore

/// Complete original pair and both signed coefficient laws, never rounded circles.
public struct OriginalCoaxialSurfacePairSnapshot: Sendable {
    public let original: OriginalCoaxialSurfacePairInput
    public let first: OriginalSourceBinding<OriginalAnalyticCoordinateSnapshot>
    public let second: OriginalSourceBinding<OriginalAnalyticCoordinateSnapshot>
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, OriginalPhysicalAngleScalarDomain>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, OriginalPhysicalAngleScalarDomain>
    public let coneIsFirst: Bool
    public let field: OriginalPhysicalAngleScalarDomain
    public let radius: OriginalPhysicalAngleValue
    public let positiveSlant: OriginalPhysicalAngleValue
    public let positiveRelativeHeight: OriginalPhysicalAngleValue
    public let labelPeriod: OriginalPhysicalAngleValue
    public let centerX: OriginalPhysicalAngleValue
    public let centerY: OriginalPhysicalAngleValue
    public let coneOriginZ: OriginalPhysicalAngleValue
    public let cylinderOriginZ: OriginalPhysicalAngleValue
    public let proofDepth: ExactScalarDepth
    public func slant<A: ExactScalarAdmission & ~Copyable>(positive: Bool, using a: inout A) throws -> OriginalPhysicalAngleValue {
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        return positive ? positiveSlant : try field.negated(positiveSlant, using: &a)
    }
    public func worldHeight<A: ExactScalarAdmission & ~Copyable>(positive: Bool, using a: inout A) throws -> OriginalPhysicalAngleValue {
        let relative = positive ? positiveRelativeHeight : try field.negated(positiveRelativeHeight, using: &a)
        return try field.adding(coneOriginZ, relative, using: &a)
    }
    public func cylinderHeight<A: ExactScalarAdmission & ~Copyable>(positive: Bool, using a: inout A) throws -> OriginalPhysicalAngleValue {
        try field.subtracting(worldHeight(positive: positive, using: &a), cylinderOriginZ, using: &a)
    }
    public func coneOffset<A: ExactScalarAdmission & ~Copyable>(positive: Bool, using a: inout A) throws -> OriginalPhysicalAngleValue {
        positive ? try field.integer(0, using: &a) : try field.dividing(labelPeriod, field.integer(2, using: &a), using: &a)
    }
}
