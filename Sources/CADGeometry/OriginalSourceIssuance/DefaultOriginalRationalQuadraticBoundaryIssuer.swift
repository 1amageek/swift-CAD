#if ORIGINAL_QUADRATIC_BOUNDARY_ISOLATED_VERIFICATION
import L0
import L1
@testable import SourceIssuer
#endif

/// Augments the actual sole-span Cox-de Boor law with a checked complete UV cap theorem.
public struct DefaultOriginalRationalQuadraticBoundaryIssuer<S: OriginalBSplineSourceReading,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalRationalQuadraticBoundaryIssuing {
    public typealias Source=S
    public typealias Field=F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        field: borrowing F,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalRationalQuadraticBoundaryReceipt<S,F> {
        let source=copy source,f=copy field
        do {
            return try admission.withProofScope { a in
                try a.checkpoint()
                guard source.sourceDepth >= 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
                guard source.sourceDepth <= limits.remainingSourceDepth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                let original=source.original
                guard original.parameterCount > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
                // FIXME(INCOMPLETE_IMPLEMENTATION): The Native/issued-face boundary consumers
                // currently receive only this full positive clamped quadratic UV authority.
                // General spans and degenerate control triangles require complete directed
                // winding evidence before their public clipping paths can succeed.
                guard original.parameterCount == 1 else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                let degree=original.degree(in:0),count=original.controlCount(in:0),knotCount=original.knotCount(in:0)
                let countAndDegree=count.addingReportingOverflow(degree),expected=countAndDegree.partialValue.addingReportingOverflow(1)
                guard !countAndDegree.overflow,!expected.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                guard degree >= 1,count > degree,knotCount == expected.partialValue else { throw OriginalSourceIssuanceFailure.invalidSource }
                guard degree == 2,count == 3,knotCount == 6,!original.isPeriodic(in:0) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:F.Value.self))
                var knots:[F.Value]=[];knots.reserveCapacity(6)
                for i in 0..<6 {
                    try a.consumeWork(1)
                    let value=original.knot(at:i,in:0)
                    guard value.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
                    let exact=try f.binary64(exactly:value,using:&a)
                    if let previous=knots.last,try f.compare(previous,exact,using:&a) == .greater { throw OriginalSourceIssuanceFailure.invalidSource }
                    knots.append(exact)
                }
                let lower=knots[2],upper=knots[3]
                guard try f.compare(lower,upper,using:&a) == .less else { throw OriginalSourceIssuanceFailure.invalidSource }
                for i in 0..<3 {
                    guard try f.compare(knots[i],lower,using:&a) == .equal,
                        try f.compare(knots[i+3],upper,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:[F.Value].self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:F.Value.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:F.Value.self))
                var points:[[F.Value]]=[],weights:[F.Value]=[];points.reserveCapacity(3);weights.reserveCapacity(3)
                for i in 0..<3 {
                    try a.consumeWork(1)
                    let x=original.coordinate(ofControl:i,in:0),y=original.coordinate(ofControl:i,in:1)
                    let w=original.weight(ofControl:i)
                    guard x.isFinite,y.isFinite,w.isFinite,w > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
                    points.append([try f.binary64(exactly:x,using:&a),try f.binary64(exactly:y,using:&a)])
                    let weight=try f.binary64(exactly:w,using:&a)
                    guard try f.sign(of:weight,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
                    weights.append(weight)
                }
                let dx1=try f.subtracting(points[1][0],points[0][0],using:&a),dy1=try f.subtracting(points[1][1],points[0][1],using:&a)
                let dx2=try f.subtracting(points[2][0],points[0][0],using:&a),dy2=try f.subtracting(points[2][1],points[0][1],using:&a)
                let determinant=try f.subtracting(f.multiplying(dx1,dy2,using:&a),f.multiplying(dy1,dx2,using:&a),using:&a)
                guard try f.sign(of:determinant,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:[F.Value].self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:9,of:F.Value.self))
                var rows:[[F.Value]]=[];rows.reserveCapacity(3)
                for i in 0..<3 {
                    let j=(i+1)%3,k=(i+2)%3
                    rows.append([try f.dividing(f.subtracting(points[j][1],points[k][1],using:&a),determinant,using:&a),
                        try f.dividing(f.subtracting(points[k][0],points[j][0],using:&a),determinant,using:&a),
                        try f.dividing(f.subtracting(f.multiplying(points[j][0],points[k][1],using:&a),f.multiplying(points[k][0],points[j][1],using:&a),using:&a),determinant,using:&a)])
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                let chart=try source.chart(OriginalBSplineChartSelection(spans:[2]),limits:limits,using:&a)
                // The existing generic issuer is the sole original position-law producer.
                let law=try DefaultOriginalBSplineChartIssuer<S,F>().issue(source:source,chart:chart,field:f,limits:limits,using:&a)
                try law.admitProof(using:&a)
                guard law.support.count == 1,law.homogeneous.count == 4,
                    try f.compare(law.support[0].lower,lower,using:&a) == .equal,
                    try f.compare(law.support[0].upper,upper,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
                let ring=law.polynomials,one=try f.integer(1,using:&a)
                let t=try ring.variable(0,using:&a)
                let tau=try ring.scaled(ring.subtracting(t,ring.constant(lower,using:&a),using:&a),by:f.dividing(one,f.subtracting(upper,lower,using:&a),using:&a),using:&a)
                let complement=try ring.subtracting(ring.constant(one,using:&a),tau,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:ExactPolynomial<F>.self))
                let bernstein=[try ring.multiplying(complement,complement,using:&a),
                    try ring.scaled(ring.multiplying(tau,complement,using:&a),by:f.integer(2,using:&a),using:&a),
                    try ring.multiplying(tau,tau,using:&a)]
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<F>.self))
                var residuals:[ExactPolynomial<F>]=[];residuals.reserveCapacity(4)
                var sum=try ring.zero(using:&a)
                for i in 0..<3 {
                    try a.consumeWork(1)
                    let barycentric=try ring.adding(ring.adding(ring.scaled(law.homogeneous[0],by:rows[i][0],using:&a),
                        ring.scaled(law.homogeneous[1],by:rows[i][1],using:&a),using:&a),ring.scaled(law.denominator,by:rows[i][2],using:&a),using:&a)
                    let weighted=try ring.scaled(bernstein[i],by:weights[i],using:&a)
                    let residual=try ring.subtracting(barycentric,weighted,using:&a)
                    guard try ring.isZero(residual,using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
                    residuals.append(residual);sum=try ring.adding(sum,weighted,using:&a)
                }
                let denominatorResidual=try ring.subtracting(law.denominator,sum,using:&a)
                guard try ring.isZero(denominatorResidual,using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
                residuals.append(denominatorResidual)
                // Positive Bernstein weights give W>0 on the entire closed span.
                // The nonnegative barycentric conic branch has the unique inverse
                // tau=w0*lambda1/(2*w1*lambda0+w0*lambda1), except P2 where tau=1.
                // Thus the retained identities prove the full directed arc and cap.
                let depth=try a.depth
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRationalQuadraticBoundaryReceipt<S,F>.self))
                let result=OriginalRationalQuadraticBoundaryReceipt(law:law,first:points[0],last:points[2],
                    barycentricRows:rows,weights:weights,determinant:determinant,identityResiduals:residuals,proofDepth:depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
