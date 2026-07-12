public extension FeatureOperation {
    var capabilityOperation: String {
        switch self {
        case .sketch: return "sketch"
        case .extrude: return "extrude"
        case .revolve: return "revolve"
        case .sweep: return "sweep"
        case .loft: return "loft"
        case .boolean: return "boolean"
        case .polySpline: return "polySpline"
        case .bSplineSurface: return "bSplineSurface"
        case .faceLoopOffset: return "faceLoopOffset"
        case .edgeOffset: return "edgeOffset"
        case .faceKnife: return "faceKnife"
        case .faceDelete: return "faceDelete"
        case .faceDraft: return "faceDraft"
        case .bridgeCurve: return "bridgeCurve"
        case .curveEdit: return "curveEdit"
        case .curveOffset: return "curveOffset"
        case .curveTrim: return "curveTrim"
        }
    }
}
