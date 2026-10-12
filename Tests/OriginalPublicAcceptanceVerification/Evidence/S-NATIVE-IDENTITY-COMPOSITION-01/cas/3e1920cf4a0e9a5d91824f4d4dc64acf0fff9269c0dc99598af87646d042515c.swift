#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Both nappes and the apex of the original full-domain cone, without rounded trig.
public struct DefaultOriginalConeImageIssuer<Source: OriginalConeImageReading,
    Field: ExactPhysicalAngleCoefficients>: OriginalImplicitImageIssuing {
    public typealias Selection = OriginalPrimitiveImageSelection
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source,Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalImplicitImageReceipt<Source,Selection,Field> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            try source.require(limits)
            guard source.owns(chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            let original = source.original
            guard original.physicalHalfAngle == field.originalRadians else {
                throw OriginalSourceIssuanceFailure.scalar(.incompatibleDomain)
            }
            let s = try field.sine(using:&admission), c = try field.cosine(using:&admission)
            let angle = try field.binary64(exactly:original.physicalHalfAngle,using:&admission)
            guard try field.sign(of:angle,using:&admission) == .positive,
                try field.sign(of:s,using:&admission) == .positive,
                try field.sign(of:c,using:&admission) == .positive else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            let coordinates = try OriginalImageLocalCoordinates(source:original,field:field,
                requireIdentity:false,using:&admission)
            let ring = coordinates.ring, local = coordinates.local
            let radial = try ring.adding(ring.multiplying(local[0],local[0],using:&admission),
                ring.multiplying(local[1],local[1],using:&admission),using:&admission)
            let equation = try ring.subtracting(ring.scaled(radial,
                by:field.multiplying(c,c,using:&admission),using:&admission),
                ring.scaled(ring.multiplying(local[2],local[2],using:&admission),
                    by:field.multiplying(s,s,using:&admission),using:&admission),using:&admission)
            let guardLaw = try ring.constant(coordinates.determinant,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactPolynomial<Field>.self))
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,
                of:OriginalImplicitImageReceipt<Source,Selection,Field>.self))
            let result = OriginalImplicitImageReceipt(chart:copy chart,field:copy field,
                polynomials:ring,equation:equation,nonzeroGuards:[guardLaw])
            try admission.checkpoint()
            return result
        } catch { throw .init(preserving:error) }
    }
}
