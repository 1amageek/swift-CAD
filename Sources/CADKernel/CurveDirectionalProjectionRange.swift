import CADCore

public enum CurveDirectionalProjectionRange: Sendable, Hashable {
    case line
    case ray

    func accepts(_ signedDistance: Double, tolerance: ModelingTolerance) -> Bool {
        switch self {
        case .line:
            return true
        case .ray:
            return signedDistance >= -tolerance.distance
        }
    }
}
