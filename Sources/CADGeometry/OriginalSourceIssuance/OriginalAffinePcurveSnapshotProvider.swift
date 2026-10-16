#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Original affine pcurve validation requires the target C math module.")
#endif
import CADCore

public struct OriginalAffinePcurveSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalExactScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalExactScalarDomain, tolerance: ModelingTolerance) { self.field=field; self.tolerance=tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceParameterCurve,
        limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalAffinePcurveSnapshot> {
        let input=copy input
        do {
            return try admission.withProofScope { a in
                try a.checkpoint(); try a.consumeWork(1); try tolerance.validate()
                let f=field, ring=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
                let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),t=try ring.variable(0,using:&a)
                func scalar(_ value: Double) throws -> OriginalExactScalar {
                    try a.consumeWork(1)
                    guard value.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
                    return try f.binary64(exactly:value,using:&a)
                }
                func interpolation(_ start: Double,_ end: Double) throws -> ExactPolynomial<OriginalExactScalarDomain> {
                    let first=try scalar(start),last=try scalar(end)
                    return try ring.adding(ring.constant(first,using:&a),ring.scaled(t,by:f.subtracting(last,first,using:&a),using:&a),using:&a)
                }
                let u: ExactPolynomial<OriginalExactScalarDomain>,v: ExactPolynomial<OriginalExactScalarDomain>
                switch input {
                case .affine(let origin,let direction,let start,let end):
                    guard hypot(direction.x,direction.y)>Double.ulpOfOne,end-start>tolerance.distance else {
                        throw OriginalSourceIssuanceFailure.invalidSource
                    }
                    let parameter=try interpolation(start,end)
                    u=try ring.adding(ring.constant(scalar(origin.x),using:&a),ring.scaled(parameter,by:scalar(direction.x),using:&a),using:&a)
                    v=try ring.adding(ring.constant(scalar(origin.y),using:&a),ring.scaled(parameter,by:scalar(direction.y),using:&a),using:&a)
                case .constantU(let value,let start,let end):
                    guard abs(end-start)>Double.ulpOfOne else { throw OriginalSourceIssuanceFailure.invalidSource }
                    u=try ring.constant(scalar(value),using:&a); v=try interpolation(start,end)
                case .constantV(let value,let start,let end):
                    guard abs(end-start)>Double.ulpOfOne else { throw OriginalSourceIssuanceFailure.invalidSource }
                    u=try interpolation(start,end); v=try ring.constant(scalar(value),using:&a)
                default:
                    // FIXME(INCOMPLETE_IMPLEMENTATION): General pcurve supply still needs original
                    // polyline/angular/implicit/certified/transformed parameter laws. This source
                    // port refuses those branches until their complete retained cover is issued.
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<OriginalExactScalarDomain>.self))
                let position=[u,v,try ring.constant(zero,using:&a),try ring.constant(one,using:&a)]
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalAffinePcurveSnapshot.self))
                let result=OriginalAffinePcurveSnapshot(original:input,field:f,polynomials:ring,
                    position:position,lower:zero,upper:one,depth:try a.depth)
                try a.checkpoint();return .init(original:result,sourceDepth:0)
            }
        } catch { throw .init(preserving:error) }
    }
}
