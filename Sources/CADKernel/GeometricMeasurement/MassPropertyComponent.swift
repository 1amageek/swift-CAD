import CADCore
import CADGeometry

public struct MassPropertyComponent: Sendable, Hashable {
    public let bodyID: BodyID
    public let densityKilogramsPerCubicMeter: Double?
    public let placement: RigidTransform3D
    public let affinePlacement: AffineTransform3D?
    public init(bodyID: BodyID, densityKilogramsPerCubicMeter: Double? = nil,
        placement: RigidTransform3D = .translated(by: .zero)) {
        self.bodyID = bodyID; self.densityKilogramsPerCubicMeter = densityKilogramsPerCubicMeter; self.placement = placement
        self.affinePlacement = nil
    }
    public init(bodyID: BodyID, densityKilogramsPerCubicMeter: Double? = nil,
        affinePlacement: AffineTransform3D) {
        self.bodyID = bodyID
        self.densityKilogramsPerCubicMeter = densityKilogramsPerCubicMeter
        self.placement = .translated(by: .zero)
        self.affinePlacement = affinePlacement
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try validateTransport(using: &execution)
        try placement.validate(tolerance: tolerance)
        try execution.checkpoint()
    }

    private func validateTransport(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try placement.basisX.validate(); try placement.basisY.validate()
        try placement.basisZ.validate(); try placement.translation.validate()
        if let affinePlacement {
            guard placement == .translated(by: .zero) else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                    message: "An affine mass occurrence must retain one original placement authority.")
            }
            try affinePlacement.validate()
            _ = try affinePlacement.originalDeterminantSign(using: &execution)
        }
        if let densityKilogramsPerCubicMeter {
            guard densityKilogramsPerCubicMeter.isFinite, densityKilogramsPerCubicMeter >= 0 else {
                throw GeometryError.invalidDistance(densityKilogramsPerCubicMeter)
            }
        }
    }
}

#if !hasFeature(Embedded)
extension MassPropertyComponent: Codable {
    private enum CodingKeys: String, CodingKey { case bodyID, densityKilogramsPerCubicMeter, placement, affinePlacement }
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.bodyID, .densityKilogramsPerCubicMeter, .placement, .affinePlacement], in: decoder)
        bodyID = try c.decode(BodyID.self, forKey: .bodyID)
        densityKilogramsPerCubicMeter = try c.decodeIfPresent(Double.self, forKey: .densityKilogramsPerCubicMeter)
        placement = try c.decode(RigidTransform3D.self, forKey: .placement)
        affinePlacement = try c.decodeIfPresent(AffineTransform3D.self, forKey: .affinePlacement)
        try validateTransport(using: &execution)
    }
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validateTransport(using: &execution)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bodyID, forKey: .bodyID)
        try c.encodeIfPresent(densityKilogramsPerCubicMeter, forKey: .densityKilogramsPerCubicMeter)
        try c.encode(placement, forKey: .placement)
        try c.encodeIfPresent(affinePlacement, forKey: .affinePlacement)
    }
}
#endif
