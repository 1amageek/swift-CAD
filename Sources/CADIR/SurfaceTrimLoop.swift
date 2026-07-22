import CADCore
import CADGeometry

public enum SurfaceTrimLoopRole: String, Codable, CaseIterable, Hashable, Sendable {
    case outer
    case inner
}

public struct SurfaceTrimLoop: Codable, Hashable, Sendable {
    public let role: SurfaceTrimLoopRole
    public let parameterCurves: [SurfaceParameterCurve]

    public init(
        role: SurfaceTrimLoopRole,
        parameterCurves: [SurfaceParameterCurve]
    ) {
        self.role = role
        self.parameterCurves = parameterCurves
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard parameterCurves.count >= 2 else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: Double(parameterCurves.count),
                tolerance: tolerance,
                message: "A surface trim loop requires at least two exact pcurve spans."
            )
        }
        guard parameterCurves.count <= 4_096 else {
            throw KernelError(
                phase: .validation,
                code: .resourceLimitExceeded,
                residual: Double(parameterCurves.count),
                tolerance: tolerance,
                message: "A surface trim loop exceeded the exact pcurve span budget."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case parameterCurves
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.role, .parameterCurves], in: decoder)
        role = try container.decode(SurfaceTrimLoopRole.self, forKey: .role)
        parameterCurves = try container.decode(
            [SurfaceParameterCurve].self,
            forKey: .parameterCurves
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(parameterCurves, forKey: .parameterCurves)
    }
}
