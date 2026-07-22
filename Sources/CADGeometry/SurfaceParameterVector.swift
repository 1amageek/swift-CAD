import CADCore

public struct SurfaceParameterVector: Sendable, Hashable {
    public let u: Double
    public let v: Double

    public init(u: Double, v: Double) throws {
        guard u.isFinite, v.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "A surface parameter vector requires finite components."
            )
        }
        self.u = u
        self.v = v
    }
}
