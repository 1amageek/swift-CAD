import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import struct CADGeometry.ScalarInterval
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
import struct CADGeometry.SurfaceParameterBox
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
import SourceGeometryAdapters
#endif

/// Original source bindings and complete exact parameter selection/incidence.
public struct NativeExactParametricRelation: Sendable {
    public let source: NativeExactRelationSource
    public let domains: NativeExactRelationDomains
    public let tolerance: ModelingTolerance
    public let coefficientField: ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let relation: ExactParametricRelation<ExactRationalScalarDomain>

    init(source: NativeExactRelationSource, domains: NativeExactRelationDomains, tolerance: ModelingTolerance,
        coefficientField: ExactAlgebraicScalarDomain<ExactRationalScalarDomain>,
        relation: ExactParametricRelation<ExactRationalScalarDomain>) {
        self.source = source; self.domains = domains; self.tolerance = tolerance
        self.coefficientField = coefficientField; self.relation = relation
    }
}
