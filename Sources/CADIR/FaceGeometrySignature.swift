import CADCore
import CADGeometry
import CADTopology

public struct FaceGeometrySignature: Hashable, Sendable {
    public let surface: Surface3D
    public let orientation: Orientation
    public let loops: [LoopGeometrySignature]

    public init(
        surface: Surface3D,
        orientation: Orientation,
        loops: [LoopGeometrySignature]
    ) {
        self.surface = surface
        self.orientation = orientation
        self.loops = loops
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try surface.validate(tolerance: GeometrySignatureValidation.tolerance, using: &execution)
        for loop in loops {
            try loop.validate(on: surface, using: &execution)
        }
    }

    func chargeStructuralComparison(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        for loop in loops { try loop.chargeStructuralComparison(using: &execution) }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case surface
        case orientation
        case loops
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(Set(CodingKeys.allCases), in: decoder)
        surface = try container.decode(Surface3D.self, forKey: .surface)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        loops = try container.decode([LoopGeometrySignature].self, forKey: .loops)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(loops, forKey: .loops)
    }
#endif
}

#if !hasFeature(Embedded)
extension FaceGeometrySignature: Codable {}
#endif
