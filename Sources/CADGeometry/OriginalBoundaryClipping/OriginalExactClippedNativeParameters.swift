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

/// Immutable complete raw/refined parameter correspondence; all chart and lift owners survive.
public struct OriginalExactClippedNativeParameters: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let boundary: OriginalExactNativeBoundaryDomain
    public let selection: OriginalNativeBoundaryDomain.Selection
    /// Array ordinal is the retained raw family pair ordinal, including empty refinements.
    public let refinements: [OriginalExactBoundaryRefinement]
    init(boundary: OriginalExactNativeBoundaryDomain,selection: OriginalNativeBoundaryDomain.Selection,
        refinements: [OriginalExactBoundaryRefinement]) {
        self.boundary = boundary;self.selection = selection;self.refinements = refinements
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(originalCoordinates: [Field.Value],
        queryField: Field? = nil,domainLimits: OriginalDomainIdentityLimits,rootLimits: ExactRealRootLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            let field = queryField ?? boundary.source.surfaceCover.space.frame.scalarField
            try boundary.source.admitted(limits:domainLimits,queryField:field,using:&admission)
            let arity: Int
            switch boundary.source { case .curveSurface:arity = 3;case .firstSurface,.secondSurface:arity = 4 }
            guard originalCoordinates.count == arity else { throw NativeExactRelationFailure.invalidDomain }
            for value in originalCoordinates { try admission.consumeWork(1);_ = try field.sign(of:value,using:&admission) }
            for index in refinements.indices {
                try admission.consumeWork(1)
                if let local = try boundary.source.localCoordinates(at:index,original:originalCoordinates,queryField:field,limits:domainLimits,using:&admission),
                    try refinements[index].parameters.contains(localCoordinates:local,queryField:field,rootLimits:rootLimits,using:&admission) {
                    try admission.checkpoint();return true
                }
            }
            try admission.checkpoint();return false
        } catch { throw .preserving(error) }
    }
}
