import CADCore

/// Retains the existing exact arc-length field rather than rounding its stations.
public struct OriginalPolylinePcurveSnapshotProvider: OriginalSourceSnapshotting {
    public let maximumValueDepth: Int
    public let maximumCoefficientDepth: Int
    public let initialField: OriginalExactScalarDomain?
    public init(maximumValueDepth: Int, maximumCoefficientDepth: Int) {
        self.maximumValueDepth=maximumValueDepth; self.maximumCoefficientDepth=maximumCoefficientDepth
        initialField=nil
    }
    public init(field: OriginalExactScalarDomain) {
        initialField=field;maximumValueDepth=field.maximumValueDepth
        maximumCoefficientDepth=field.maximumCoefficientDepth
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceParameterCurve,
        limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalPolylinePcurveSnapshot> {
        let original=copy input
        do {
            return try admission.withProofScope { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard maximumValueDepth >= 0, maximumCoefficientDepth >= 0,
                    case .polyline(let points) = original else { throw OriginalSourceIssuanceFailure.invalidSource }
                let maximum=try ExactScalarDepth(value:maximumValueDepth,coefficient:maximumCoefficientDepth)
                let inherited=initialField?.originalDepth ?? .init(uncheckedValue:0,coefficient:0)
                let prepared=try ExactScalarNumericAccess.withAdmission(&a,inherited:inherited,maximum:maximum) { usage in
                    try OriginalEuclideanPolylineParameterLaw(originalPoints:points,in:initialField?.context,inheritedDepth:0,
                        maximumAlgebraicDepth:maximumCoefficientDepth,usage:&usage)
                }
                let law=prepared.value
                let retained=OriginalExactScalar(original:law.totalLength,depth:prepared.depth)
                let field=try OriginalExactScalarDomain(retaining:retained,maximumValueDepth:maximumValueDepth,
                    maximumCoefficientDepth:maximumCoefficientDepth,using:&a)
                let ring=try ExactPolynomialDomain(field:field,variableCount:1,using:&a)
                let t=try ring.variable(0,using:&a),zero=try field.integer(0,using:&a),one=try field.integer(1,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:law.segments.count,of:[ExactPolynomial<OriginalExactScalarDomain>].self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:law.segments.count,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                var positions:[[ExactPolynomial<OriginalExactScalarDomain>]]=[]
                var bounds:[OriginalSourceParameterInterval<OriginalExactScalar>]=[]
                positions.reserveCapacity(law.segments.count); bounds.reserveCapacity(law.segments.count)
                for segment in law.segments {
                    try a.consumeWork(1)
                    let coefficients=try ExactScalarNumericAccess.withAdmission(&a,inherited:prepared.depth,maximum:maximum) { usage in
                        let derivative=try segment.originalFirstDerivative(maximumAlgebraicDepth:maximumCoefficientDepth,usage:&usage)
                        return (derivative.u,derivative.v)
                    }
                    func value(_ source: OriginalSingularFieldElement, depth: ExactScalarDepth) throws -> OriginalExactScalar {
                        try field.importing(OriginalExactScalar(original:source,depth:depth),using:&a)
                    }
                    let lower=try value(segment.lowerFraction,depth:prepared.depth)
                    let upper=try value(segment.upperFraction,depth:prepared.depth)
                    let local=try ring.subtracting(t,ring.constant(lower,using:&a),using:&a)
                    let u=try ring.adding(ring.constant(field.rational(exactly:segment.originalUStart,using:&a),using:&a),
                        ring.scaled(local,by:value(coefficients.value.0,depth:coefficients.depth),using:&a),using:&a)
                    let v=try ring.adding(ring.constant(field.rational(exactly:segment.originalVStart,using:&a),using:&a),
                        ring.scaled(local,by:value(coefficients.value.1,depth:coefficients.depth),using:&a),using:&a)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<OriginalExactScalarDomain>.self))
                    positions.append([u,v,try ring.constant(zero,using:&a),try ring.constant(one,using:&a)])
                    bounds.append(.init(lower:lower,upper:upper))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPolylinePcurveSnapshot.self))
                let source=OriginalPolylinePcurveSnapshot(original:original,law:law,field:field,polynomials:ring,
                    depth:try a.depth,positions:positions,bounds:bounds)
                try a.checkpoint(); return .init(original:source,sourceDepth:0)
            }
        } catch { throw .init(preserving:error) }
    }
}
