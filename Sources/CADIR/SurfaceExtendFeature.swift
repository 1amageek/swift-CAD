import CADCore
import CADGeometry

public struct SurfaceExtendFeature: Codable, Hashable, Sendable {
    public let target: SurfaceOperationTargetReference
    public let uDomain: ParameterDomain
    public let vDomain: ParameterDomain

    public init(
        target: SurfaceOperationTargetReference,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain
    ) {
        self.target = target
        self.uDomain = uDomain
        self.vDomain = vDomain
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try target.validate()
        try uDomain.validate(tolerance: tolerance)
        try vDomain.validate(tolerance: tolerance)
        guard case .closed = uDomain, case .closed = vDomain else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface extend requires finite target U and V domains."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case uDomain
        case vDomain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .uDomain, .vDomain],
            in: decoder
        )
        target = try container.decode(SurfaceOperationTargetReference.self, forKey: .target)
        uDomain = try container.decode(ParameterDomain.self, forKey: .uDomain)
        vDomain = try container.decode(ParameterDomain.self, forKey: .vDomain)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(uDomain, forKey: .uDomain)
        try container.encode(vDomain, forKey: .vDomain)
    }
}
