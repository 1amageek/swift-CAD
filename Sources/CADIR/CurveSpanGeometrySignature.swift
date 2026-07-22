import CADCore
import CADGeometry

public struct CurveSpanGeometrySignature: Codable, Hashable, Sendable {
    public let curve: Curve3D
    public let startParameter: Double?
    public let endParameter: Double?
    public let startPoint: Point3D
    public let endPoint: Point3D

    public init(
        curve: Curve3D,
        startParameter: Double?,
        endParameter: Double?,
        startPoint: Point3D,
        endPoint: Point3D
    ) {
        self.curve = curve
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public func validate() throws {
        try curve.validate(tolerance: GeometrySignatureValidation.tolerance)
        try startPoint.validate()
        try endPoint.validate()
        guard startPoint != endPoint,
              (startParameter == nil) == (endParameter == nil) else {
            throw invalidSignature("Curve-span geometry requires distinct endpoints and a complete optional trim.")
        }
        if let startParameter, let endParameter {
            guard startParameter.isFinite,
                  endParameter.isFinite,
                  startParameter != endParameter else {
                throw invalidSignature("Curve-span geometry requires a finite non-degenerate trim.")
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case curve
        case startParameter
        case endParameter
        case startPoint
        case endPoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(Set(CodingKeys.allCases), in: decoder)
        curve = try container.decode(Curve3D.self, forKey: .curve)
        startParameter = try container.decodeIfPresent(Double.self, forKey: .startParameter)
        endParameter = try container.decodeIfPresent(Double.self, forKey: .endParameter)
        startPoint = try container.decode(Point3D.self, forKey: .startPoint)
        endPoint = try container.decode(Point3D.self, forKey: .endPoint)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encodeIfPresent(startParameter, forKey: .startParameter)
        try container.encodeIfPresent(endParameter, forKey: .endParameter)
        try container.encode(startPoint, forKey: .startPoint)
        try container.encode(endPoint, forKey: .endPoint)
    }

    private func invalidSignature(_ message: String) -> KernelError {
        KernelError(
            phase: .validation,
            code: .invalidInput,
            tolerance: nil,
            message: message
        )
    }
}
