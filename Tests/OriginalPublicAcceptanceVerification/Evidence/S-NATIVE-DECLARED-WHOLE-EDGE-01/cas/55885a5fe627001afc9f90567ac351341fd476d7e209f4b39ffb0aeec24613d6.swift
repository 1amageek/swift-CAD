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

/// Owns every original chart/lift pair, scoped exclusion proof and complete raw/refined correspondence.
public struct OriginalExactNativeSelfContacts: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let raw: NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>
    /// The selected authored-coordinate diagonal is first; subsequent receipts retain caller roles.
    public let identities: [OriginalParameterIdentity<BSplineSurface3D,Field>]
    /// Ordinals correspond to `raw.pieces`, including empty refinements.
    public let refinements: [NativeExactParameterRefinement]
    init(raw: NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>,
        identities: [OriginalParameterIdentity<BSplineSurface3D,Field>],refinements: [NativeExactParameterRefinement]) {
        self.raw = raw;self.identities = identities;self.refinements = refinements
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(firstTuple: [Field.Value],secondTuple: [Field.Value],
        queryField: Field? = nil,domainLimits: OriginalDomainIdentityLimits,rootLimits: ExactRealRootLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            guard firstTuple.count == 2,secondTuple.count == 2 else { throw NativeExactRelationFailure.invalidDomain }
            let field = queryField ?? raw.first.effective.frame.scalarField
            for value in firstTuple { try admission.consumeWork(1);_ = try field.sign(of:value,using:&admission) }
            for value in secondTuple { try admission.consumeWork(1);_ = try field.sign(of:value,using:&admission) }
            _ = try raw.first.effective.contains(firstTuple,queryField:field,limits:domainLimits,using:&admission)
            _ = try raw.second.effective.contains(secondTuple,queryField:field,limits:domainLimits,using:&admission)
            let transporter = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
            for index in refinements.indices {
                try admission.consumeWork(1)
                let piece = raw.pieces[index]
                let firstIncluded = try piece.first.occurrence.selectedImage.contains(firstTuple,queryField:field,limits:domainLimits,using:&admission)
                let secondIncluded = try piece.second.occurrence.selectedImage.contains(secondTuple,queryField:field,limits:domainLimits,using:&admission)
                guard firstIncluded,secondIncluded else { continue }
                let left = try transporter.forward(firstTuple,through:piece.first.inverse,queryField:field,limits:domainLimits,using:&admission)
                let right = try transporter.forward(secondTuple,through:piece.second.inverse,queryField:field,limits:domainLimits,using:&admission)
                let count = left.count.addingReportingOverflow(right.count)
                guard !count.overflow else { throw ExactScalarFailure.countOverflow }
                try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Field.Value.self))
                var coordinates = left;coordinates.append(contentsOf:right)
                if try refinements[index].contains(localCoordinates:coordinates,queryField:field,rootLimits:rootLimits,using:&admission) {
                    try admission.checkpoint();return true
                }
            }
            try admission.checkpoint();return false
        } catch { throw .preserving(error) }
    }
}
