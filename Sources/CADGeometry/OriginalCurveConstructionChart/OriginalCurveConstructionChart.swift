/// Sole persistent authority for a normalized original traversal.
public enum OriginalCurveConstructionChart: Hashable, Sendable {
  case traversal(OriginalCurveRootSpan3D)
  case parameterLaw(OriginalCurveConstructionParameterSource)

  public var source: Curve3D {
    switch self {
    case .traversal(let traversal): traversal.source
    case .parameterLaw(let value): value.source
    }
  }
}
