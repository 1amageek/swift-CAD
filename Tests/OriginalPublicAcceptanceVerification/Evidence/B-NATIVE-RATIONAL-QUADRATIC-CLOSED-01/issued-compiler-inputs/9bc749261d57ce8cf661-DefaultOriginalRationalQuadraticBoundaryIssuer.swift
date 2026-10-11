import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import enum PublicLiftPlane.NativeExactGeometryPublicationFailure
import enum PublicLiftPlane.GeometryExactScalarFailure
import struct PublicLiftPlane.DefaultExactOriginalScalarTransporter
import class PublicLiftPlane.ExactAlgebraicCalculation
import struct PublicLiftPlane.ExactAlgebraicEmbedding
import protocol PublicLiftPlane.ExactAlgebraicExtending
import struct PublicLiftPlane.ExactAlgebraicExtension
import struct PublicLiftPlane.ExactAlgebraicScalar
import struct PublicLiftPlane.ExactAlgebraicScalarDomain
import struct PublicLiftPlane.ExactOriginalScalarTransferReceipt
import protocol PublicLiftPlane.ExactOriginalScalarTransferring
import struct PublicLiftPlane.ExactRealRoot
import enum PublicLiftPlane.ExactRealRootBound
import enum PublicLiftPlane.ExactRealRootClassification
import struct PublicLiftPlane.ExactRealRootCount
import struct PublicLiftPlane.ExactRealRootDomain
import enum PublicLiftPlane.ExactRealRootFailure
import struct PublicLiftPlane.ExactRealRootInterval
import struct PublicLiftPlane.ExactRealRootLimits
import protocol PublicLiftPlane.ExactRealRootPreparing
import protocol PublicLiftPlane.ExactRealRootProducing
import protocol PublicLiftPlane.ExactRealRootQuerying
import struct PublicLiftPlane.ExactRealRootSeparation
import struct PublicLiftPlane.ExactRealRootSet
import struct PublicLiftPlane.ExactRealRootSigns
import struct PublicLiftPlane.ExactRealRootSource
import struct PublicLiftPlane.ExactRealRootTransport
import protocol PublicLiftPlane.ExactRealRootTransporting
import struct PublicLiftPlane.ExactRealCellBoundaryRoot
import struct PublicLiftPlane.ExactRealCellCondition
import struct PublicLiftPlane.ExactRealCellDefinition
import struct PublicLiftPlane.ExactRealCellDefinitionStep
import protocol PublicLiftPlane.ExactRealCellDescribing
import struct PublicLiftPlane.ExactRealCellDomain
import enum PublicLiftPlane.ExactRealCellFailure
import struct PublicLiftPlane.ExactRealCellID
import enum PublicLiftPlane.ExactRealCellInstruction
import enum PublicLiftPlane.ExactRealCellKind
import struct PublicLiftPlane.ExactRealCellLimits
import struct PublicLiftPlane.ExactRealCellPartition
import struct PublicLiftPlane.ExactRealCellPredicate
import protocol PublicLiftPlane.ExactRealCellPreparing
import protocol PublicLiftPlane.ExactRealCellProducing
import struct PublicLiftPlane.ExactRealCellProjectionBinding
import struct PublicLiftPlane.ExactRealCellProjectionEvidence
import enum PublicLiftPlane.ExactRealCellProjectionWitness
import protocol PublicLiftPlane.ExactRealCellQuerying
import struct PublicLiftPlane.ExactRealCellSample
import protocol PublicLiftPlane.ExactRealCellSelecting
import struct PublicLiftPlane.ExactRealCellSelection
import struct PublicLiftPlane.ExactRealCellSignInvariant
import enum PublicLiftPlane.ExactRealCellSignRelation
import struct PublicLiftPlane.ExactRealCellSource
import struct PublicLiftPlane.ExactRealCellStackEvidence
import protocol PublicLiftPlane.ExactRealCellTraversing
import struct PublicLiftPlane.ExactRealCellView
import struct PublicLiftPlane.ExactRealAttachment
import struct PublicLiftPlane.ExactRealCellPullback
import protocol PublicLiftPlane.ExactRealCellPullbackResolving
import struct PublicLiftPlane.ExactRealClosure
import protocol PublicLiftPlane.ExactRealClosureProducing
import enum PublicLiftPlane.ExactRealClosureProof
import enum PublicLiftPlane.ExactRealClosureStrategy
import struct PublicLiftPlane.ExactRealComponents
import protocol PublicLiftPlane.ExactRealComponentsProducing
import struct PublicLiftPlane.ExactRealIncidence
import struct PublicLiftPlane.ExactRealIncidencePair
import protocol PublicLiftPlane.ExactRealIncidenceProducing
import struct PublicLiftPlane.ExactRealProjection
import struct PublicLiftPlane.ExactRealProjectionLifts
import protocol PublicLiftPlane.ExactRealProjectionProducing
import typealias PublicLiftPlane.ExactRealTopology
import struct PublicLiftPlane.ExactRealTopologyDomain
import struct PublicLiftPlane.ExactRealTopologyElimination
import struct PublicLiftPlane.ExactRealTopologyFactor
import enum PublicLiftPlane.ExactRealTopologyFailure
import struct PublicLiftPlane.ExactRealTopologyLimits
import protocol PublicLiftPlane.ExactRealTopologyQuerying
import struct PublicLiftPlane.ExactRealTopologyReduction
import struct PublicLiftPlane.ExactRealTopologyRegion
import struct PublicLiftPlane.ExactRealTopologySignInvariant
import struct PublicLiftPlane.ExactParametricConstraintDivision
import struct PublicLiftPlane.ExactParametricGraph
import protocol PublicLiftPlane.ExactParametricGraphConstructing
import struct PublicLiftPlane.ExactParametricGraphRelation
import struct PublicLiftPlane.ExactParametricGraphRelationSource
import protocol PublicLiftPlane.ExactParametricGraphResolving
import struct PublicLiftPlane.ExactParametricGuardDivision
import struct PublicLiftPlane.ExactParametricGuardRemainder
import struct PublicLiftPlane.ExactParametricMap
import struct PublicLiftPlane.ExactParametricRelation
import protocol PublicLiftPlane.ExactParametricRelationConstructing
import struct PublicLiftPlane.ExactParametricRelationDomain
import enum PublicLiftPlane.ExactParametricRelationFailure
import enum PublicLiftPlane.ExactParametricRelationKind
import protocol PublicLiftPlane.ExactParametricRelationResolving
import struct PublicLiftPlane.ExactParametricRelationSource
import struct PublicLiftPlane.ExactParametricSquareReduction
import struct PublicLiftPlane.DefaultExactGeometricGraphRelationResolver
import struct PublicLiftPlane.DefaultExactGeometricRelationResolver
import enum PublicLiftPlane.ExactCurveParameterBoundary
import struct PublicLiftPlane.ExactCurveParameterSpan
import enum PublicLiftPlane.ExactGeometricEvidenceKind
import struct PublicLiftPlane.ExactGeometricFiber
import struct PublicLiftPlane.ExactGeometricGraphFiber
import struct PublicLiftPlane.ExactGeometricGraphPoint
import struct PublicLiftPlane.ExactGeometricGraphRelation
import protocol PublicLiftPlane.ExactGeometricGraphRelationResolving
import struct PublicLiftPlane.ExactGeometricRelation
import enum PublicLiftPlane.ExactGeometricRelationFailure
import struct PublicLiftPlane.ExactGeometricRelationLimits
import protocol PublicLiftPlane.ExactGeometricRelationQuerying
import protocol PublicLiftPlane.ExactGeometricRelationResolving
import enum PublicLiftPlane.ExactGeometricStation
import struct PublicLiftPlane.ExactGeometricStratumID
import struct PublicLiftPlane.ExactGeometricStratumRecord
import struct PublicLiftPlane.ExactGeometricStratumView
import struct PublicLiftPlane.ExactUV
import struct PublicLiftPlane.ExactXYZ
import struct PublicLiftPlane.DefaultOriginalIssuedGraphCompiler
import struct PublicLiftPlane.DefaultOriginalIssuedGraphParameterRefiner
import struct PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver
import enum PublicLiftPlane.NativeExactRelationFailure
import protocol PublicLiftPlane.OriginalIssuedGraphCompiling
import struct PublicLiftPlane.OriginalIssuedGraphFamily
import protocol PublicLiftPlane.OriginalIssuedGraphFamilyPreparing
import struct PublicLiftPlane.OriginalIssuedGraphParameterRefinement
import protocol PublicLiftPlane.OriginalIssuedGraphParameterRefining
import struct PublicLiftPlane.OriginalIssuedGraphPreparation
import protocol PublicLiftPlane.OriginalIssuedGraphRelationOwning
import struct PublicLiftPlane.OriginalIssuedGraphRelationPair
import protocol PublicLiftPlane.OriginalIssuedGraphRelationResolving
import struct PublicLiftPlane.OriginalIssuedGraphRelations
import struct PublicLiftPlane.DefaultOriginalIssuedGeometricRelationResolver
import enum PublicLiftPlane.NativeExactGeometricRelationFailure
import struct PublicLiftPlane.OriginalIssuedExactIntersectionPoint
import struct PublicLiftPlane.OriginalIssuedGeometricRelationPair
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationReading
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationResolving
import struct PublicLiftPlane.OriginalIssuedGeometricRelations
import struct PublicLiftPlane.OriginalLiftPlaneParameterRestriction
import protocol PublicLiftPlane.OriginalPlaneGraphCompiling
import struct PublicLiftPlane.OriginalIssuedPlaneGraph
import struct PublicLiftPlane.DefaultOriginalPlaneGraphCompiler
import struct PublicLiftPlane.OriginalLiftPlaneRelations
import protocol PublicLiftPlane.OriginalLiftPlaneRelationResolving
import struct PublicLiftPlane.DefaultOriginalLiftPlaneRelationResolver
import struct PublicLiftPlane.OriginalLiftPlaneGeometricRelations
import CADCore


@testable import CADKernel
import HashTreeCollections
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
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
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
