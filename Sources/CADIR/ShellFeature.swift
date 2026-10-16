import CADCore
import CADGeometry
import CADTopology

/// Hollow: a solid walled `thickness` thick — outside it when positive (the solid becomes the
/// cavity), inside it when negative — opening through `removedFaces`, or closed when there are
/// none.
public struct ShellFeature: Hashable, Sendable {
    public let target: ShellTargetReference
    public let removedFaces: [StableSubshapeReference]
    public let thickness: CADExpression

    public init(
        target: ShellTargetReference,
        removedFaces: [StableSubshapeReference],
        thickness: CADExpression
    ) {
        self.target = target
        self.removedFaces = removedFaces
        self.thickness = thickness
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        for face in removedFaces { try face.chargeStructuralComparison(using: &execution) }
        guard (try OriginalParameterQueryStorage.set(removedFaces, using: &execution)).count == removedFaces.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Shell requires unique removed face selections."
            )
        }
        for face in removedFaces {
            try execution.consumeWork(1)
            try face.validate(using: &execution)
            guard case .face = face.geometrySignature else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    subshapeID: face.subshapeID,
                    tolerance: nil,
                    message: "Shell removal selections must be faces."
                )
            }
        }
        try thickness.validateDocumentLiteralQuantities(using: &execution)
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case removedFaces
        case thickness
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .removedFaces, .thickness], in: decoder)
        target = try container.decode(ShellTargetReference.self, forKey: .target)
        removedFaces = try container.decode([StableSubshapeReference].self, forKey: .removedFaces)
        thickness = try container.decode(CADExpression.self, forKey: .thickness)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(removedFaces, forKey: .removedFaces)
        try container.encode(thickness, forKey: .thickness)
    }
#endif
}

#if !hasFeature(Embedded)
extension ShellFeature: Codable {}
#endif
