@testable import NativeDomainAdapters
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
#endif

/// Compiles checked DI identities in each original L5 ring, then refines its retained cells once.
public struct DefaultOriginalExactNativeSelfContactQuery: OriginalExactNativeSelfContactQuerying {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public init() {}
    public func contacts<A: ExactScalarAdmission & ~Copyable>(
        in raw: NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>,
        excluding identities: [OriginalParameterIdentity<BSplineSurface3D,Field>] = [],
        domainLimits: OriginalDomainIdentityLimits,cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactNativeSelfContacts {
        do {
            try admission.checkpoint()
            guard raw.first.effective.arity == 2,raw.second.effective.arity == 2 else { throw NativeExactRelationFailure.invalidDomain }
            let anchor = try raw.second.source.chart(0,limits:domainLimits.source,using:&admission)
            guard raw.first.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let field = raw.first.effective.frame.scalarField
            let one = try field.integer(1,using:&admission),zero = try field.integer(0,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
            let transporter = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
            let left = try transporter.affine(from:raw.first.effective,to:raw.second.space.frame,
                permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:domainLimits,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
            let right = try transporter.affine(from:raw.second.effective,to:raw.second.space.frame,
                permutation:[0,1],gains:[one,one],offsets:[zero,zero],limits:domainLimits,using:&admission)
            let issuer = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
            let diagonal = try issuer.authored(left:left,right:right,limits:domainLimits,using:&admission)
            let total = identities.count.addingReportingOverflow(1)
            guard !total.overflow else { throw ExactScalarFailure.countOverflow }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:total.partialValue,of:OriginalParameterIdentity<BSplineSurface3D,Field>.self))
            var proofs = [diagonal];proofs.reserveCapacity(total.partialValue);proofs.append(contentsOf:identities)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:proofs.count,of:OriginalParameterIdentityRelation<BSplineSurface3D,Field>.self))
            var relations: [OriginalParameterIdentityRelation<BSplineSurface3D,Field>] = [];relations.reserveCapacity(proofs.count)
            let firstAnchor = try raw.first.source.chart(0,limits:domainLimits.source,using:&admission)
            for proof in proofs {
                try admission.consumeWork(1)
                let view = try issuer.relation(of:proof,limits:domainLimits,using:&admission)
                guard view.left.frame.source.owns(firstAnchor),view.right.frame.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
                guard view.left.arity == 2,view.right.arity == 2,
                    view.left.frame.coordinateSemantics.elementsEqual(raw.first.space.frame.coordinateSemantics),
                    view.right.frame.coordinateSemantics.elementsEqual(raw.second.space.frame.coordinateSemantics) else {
                    throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics
                }
                relations.append(view)
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:raw.pieces.count,of:NativeExactParameterRefinement.self))
            var refinements: [NativeExactParameterRefinement] = [];refinements.reserveCapacity(raw.pieces.count)
            for piece in raw.pieces {
                try admission.consumeWork(1)
                var compiler = try OriginalExactSelfIdentityCompiler(piece.relation,using:&admission)
                let predicate = try compiler.residual(piece:piece,identities:relations,limits:domainLimits,using:&admission)
                refinements.append(try DefaultNativeExactParameterRefiner().refine(piece.relation,matching:predicate,
                    cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission))
            }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalExactNativeSelfContacts.self))
            let result = OriginalExactNativeSelfContacts(raw:raw,identities:proofs,refinements:refinements)
            try admission.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
