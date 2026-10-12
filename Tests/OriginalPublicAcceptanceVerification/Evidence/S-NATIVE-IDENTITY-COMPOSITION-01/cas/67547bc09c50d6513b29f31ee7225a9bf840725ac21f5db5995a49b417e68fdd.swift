public enum OriginalAnalyticCoordinateKind: Sendable,Equatable {
    case circle,ellipse,hyperbola,parabola,cylinder,cone,sphere,torus
    public var arity: Int {
        switch self { case .circle,.ellipse,.hyperbola,.parabola: return 1; default: return 2 }
    }
    public func isAngular(axis: Int) -> Bool {
        if axis == 0 { return self != .hyperbola && self != .parabola }
        return axis == 1 && (self == .sphere || self == .torus)
    }
    public func isPeriodic(axis: Int) -> Bool { isAngular(axis:axis) && !(self == .sphere && axis == 1) }
}
