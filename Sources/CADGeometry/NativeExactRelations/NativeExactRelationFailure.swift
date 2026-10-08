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
public enum NativeExactRelationFailure: Error {
    case unsupportedCoverage, invalidDomain, invalidDegree
    case scalar(ExactScalarFailure)
    case root(ExactRealRootFailure)
    case cell(ExactRealCellFailure)
    case relation(ExactParametricRelationFailure)
    case domain(OriginalDomainIdentityFailure)
    case source(OriginalSourceIssuanceFailure)
    case geometry(any Error)

    static func preserving(_ error: any Error) -> Self {
        switch error {
        case let value as Self: return value
        case let value as ExactScalarFailure:
            if case .admissionRejected(let cause) = value, let native = cause as? Self { return native }
            return .scalar(value)
        case let value as OriginalDomainIdentityFailure: return .domain(value)
        case let value as OriginalSourceIssuanceFailure:
            switch value {
            case .scalar(let cause): return .preserving(cause)
            case .sourceRejected(let cause): return .preserving(cause)
            case .polynomial(let cause): return .preserving(cause)
            default: return .source(value)
            }
        case let value as ExactPolynomialFailure:
            switch value {
            case .scalar(let cause): return .preserving(cause)
            case .operationRejected(let cause): return .preserving(cause)
            default: return .geometry(value)
            }
        case let value as ExactRealRootFailure: return .root(value)
        case let value as ExactRealCellFailure: return .cell(value)
        case let value as ExactParametricRelationFailure: return .relation(value)
        default: return .geometry(error)
        }
    }
}
