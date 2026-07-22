import CADCore

public struct SurfaceIntersectionParameterPair: Codable, Sendable, Hashable {
    public let first: SurfaceParameter
    public let second: SurfaceParameter

    public init(first: SurfaceParameter, second: SurfaceParameter) throws {
        try first.validate()
        try second.validate()
        self.first = first
        self.second = second
    }

    public var values: [Double] {
        [first.u, first.v, second.u, second.v]
    }

    init(values: [Double]) throws {
        guard values.count == 4 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "A surface intersection parameter pair requires four coordinates."
            )
        }
        try self.init(
            first: SurfaceParameter(u: values[0], v: values[1]),
            second: SurfaceParameter(u: values[2], v: values[3])
        )
    }
}
