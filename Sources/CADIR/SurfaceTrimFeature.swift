import CADCore

public struct SurfaceTrimFeature: Codable, Hashable, Sendable {
    public let target: SurfaceOperationTargetReference
    public let loops: [SurfaceTrimLoop]

    public init(
        target: SurfaceOperationTargetReference,
        loops: [SurfaceTrimLoop]
    ) {
        self.target = target
        self.loops = loops
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try target.validate()
        try tolerance.validate()
        guard loops.isEmpty == false,
              loops.filter({ $0.role == .outer }).count == 1 else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface trim requires exactly one outer exact pcurve loop."
            )
        }
        guard loops.count <= 1_024 else {
            throw KernelError(
                phase: .validation,
                code: .resourceLimitExceeded,
                residual: Double(loops.count),
                tolerance: tolerance,
                message: "Surface trim exceeded the exact loop budget."
            )
        }
        for loop in loops {
            try loop.validate(tolerance: tolerance)
        }
        let spanCount = loops.reduce(into: 0) { count, loop in
            count += loop.parameterCurves.count
        }
        guard spanCount <= 16_384 else {
            throw KernelError(
                phase: .validation,
                code: .resourceLimitExceeded,
                residual: Double(spanCount),
                tolerance: tolerance,
                message: "Surface trim exceeded the total exact pcurve span budget."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case loops
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .loops], in: decoder)
        target = try container.decode(
            SurfaceOperationTargetReference.self,
            forKey: .target
        )
        loops = try container.decode([SurfaceTrimLoop].self, forKey: .loops)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(loops, forKey: .loops)
    }
}
