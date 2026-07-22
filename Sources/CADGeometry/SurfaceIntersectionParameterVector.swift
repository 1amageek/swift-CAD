import CADCore

public struct SurfaceIntersectionParameterVector: Sendable, Hashable {
    public let first: SurfaceParameterVector
    public let second: SurfaceParameterVector

    public init(first: SurfaceParameterVector, second: SurfaceParameterVector) {
        self.first = first
        self.second = second
    }

    init(values: [Double]) throws {
        guard values.count == 4 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "A surface intersection parameter vector requires four components."
            )
        }
        self.init(
            first: try SurfaceParameterVector(u: values[0], v: values[1]),
            second: try SurfaceParameterVector(u: values[2], v: values[3])
        )
    }
}
