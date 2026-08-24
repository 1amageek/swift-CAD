import CADCore

public struct SurfaceParameterBox: Codable, Equatable, Hashable, Sendable {
    public let u: ScalarInterval
    public let v: ScalarInterval

    public init(u: ScalarInterval, v: ScalarInterval) {
        self.u = u
        self.v = v
    }

    public func validate(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard u.width > 0.0, v.width > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A surface parameter box requires positive U and V spans."
            )
        }
        try validate(u, in: surface.uDomain, direction: "U", tolerance: tolerance)
        try validate(v, in: surface.vDomain, direction: "V", tolerance: tolerance)
    }

    private func validate(
        _ interval: ScalarInterval,
        in domain: ParameterDomain,
        direction: String,
        tolerance: ModelingTolerance
    ) throws {
        switch domain {
        case .unbounded, .periodic:
            return
        case let .closed(lower, upper):
            guard interval.lower >= lower, interval.upper <= upper else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "The surface parameter box extends beyond the \(direction) domain."
                )
            }
        }
    }
}
