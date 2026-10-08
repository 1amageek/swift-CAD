#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original image laws in XYZ, using the retained source's actual frame.
public struct DefaultOriginalPrimitiveImageIssuer<Source: OriginalPrimitiveImageReading,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalImplicitImageIssuing {
    public typealias Selection = OriginalPrimitiveImageSelection
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalImplicitImageReceipt<Source, Selection, Field> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            try source.require(limits)
            guard source.owns(chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            let original = source.original
            let coordinates = try OriginalImageLocalCoordinates(source: original, field: field,
                requireIdentity: original.imageKind == .sphere, using: &admission)
            let ring = coordinates.ring, local = coordinates.local, determinant = coordinates.determinant
            try admission.consumeWork(2)
            let major = try field.binary64(exactly: original.majorRadius,using:&admission)
            let minor = try field.binary64(exactly: original.minorRadius,using:&admission)
            guard try field.sign(of: major,using:&admission) == .positive else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            let radial = try ring.adding(ring.multiplying(local[0],local[0],using:&admission),
                ring.multiplying(local[1],local[1],using:&admission),using:&admission)
            let radius2 = try field.multiplying(major,major,using:&admission)
            let equation: ExactPolynomial<Field>
            switch original.imageKind {
            case .sphere:
                equation = try ring.subtracting(ring.adding(radial,
                    ring.multiplying(local[2],local[2],using:&admission),using:&admission),
                    ring.constant(radius2,using:&admission),using:&admission)
            case .cylinder:
                equation = try ring.subtracting(radial,ring.constant(radius2,using:&admission),using:&admission)
            case .torus:
                guard try field.sign(of: minor,using:&admission) == .positive,
                    try field.compare(major,minor,using:&admission) == .greater else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                let delta = try field.subtracting(radius2,field.multiplying(minor,minor,using:&admission),using:&admission)
                let total = try ring.adding(ring.adding(radial,
                    ring.multiplying(local[2],local[2],using:&admission),using:&admission),
                    ring.constant(delta,using:&admission),using:&admission)
                equation = try ring.subtracting(ring.multiplying(total,total,using:&admission),
                    ring.scaled(radial,by:field.multiplying(field.integer(4,using:&admission),radius2,using:&admission),
                        using:&admission),using:&admission)
            }
            let guardLaw = try ring.constant(determinant,using:&admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,of:ExactPolynomial<Field>.self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,of:OriginalImplicitImageReceipt<Source,Selection,Field>.self))
            let result = OriginalImplicitImageReceipt(chart:copy chart,field:copy field,
                polynomials:ring,equation:equation,nonzeroGuards:[guardLaw])
            try admission.checkpoint()
            return result
        } catch { throw .init(preserving:error) }
    }
}
