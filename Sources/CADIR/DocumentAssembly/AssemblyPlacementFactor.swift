import CADCore
import CADGeometry

/// Retains the authored transform and whether its original operation is inverted.
public enum AssemblyPlacementFactor: Equatable, Sendable {
    case forward(AssemblyPlacement)
    case inverse(AssemblyPlacement)

    public var originalPlacement: AssemblyPlacement {
        switch self { case .forward(let source), .inverse(let source): source }
    }
    public func validate(tolerance: ModelingTolerance, maximumAlgebraicDepth: Int = 32, maximumSourceDepth: Int, consumeWork: @escaping () throws -> Void) throws {
        guard case .word = originalPlacement else {
            try originalPlacement.validate(tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth, consumeWork: consumeWork)
            return
        }
        throw AssemblyError.invalidSource("A placement factor must retain a direct rigid or affine source.")
    }
    public func applying(to point: Point3D) throws -> Point3D {
        if case .word = originalPlacement { throw AssemblyError.invalidSource("A placement factor requires a direct source.") }
        switch self {
        case .forward(let source): return try source.applying(to: point)
        case .inverse(let source) where source.isExactIdentity: return point
        // FIXME(INCOMPLETE_IMPLEMENTATION): Assembly words retain the original inverse
        // operation, but the original rational inverse evaluator is not connected here.
        // Public word evaluation must fail until that law is admitted without rounding
        // the inverse matrix into a new source transform.
        case .inverse: throw AssemblyError.unsupportedOriginalPlacementOperation
        }
    }
    public func applying(to vector: Vector3D) throws -> Vector3D {
        if case .word = originalPlacement { throw AssemblyError.invalidSource("A placement factor requires a direct source.") }
        switch self {
        case .forward(let source): return try source.applying(to: vector)
        case .inverse(let source) where source.isExactIdentity: return vector
        // FIXME(INCOMPLETE_IMPLEMENTATION): The public vector path needs the same
        // retained original inverse-law evaluator as point and BRep placement.
        // Rounded inverse coefficients cannot satisfy this operation's source contract.
        case .inverse: throw AssemblyError.unsupportedOriginalPlacementOperation
        }
    }
}

#if !hasFeature(Embedded)
extension AssemblyPlacementFactor: Codable {
    private enum Keys: String, CodingKey { case operation, placement }
    private enum FamilyKeys: String, CodingKey { case kind }
    public init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: Keys.self)
        try object.validateOnlyExpectedKeys([.operation, .placement], in: decoder)
        let sourceDecoder = try object.superDecoder(forKey: .placement)
        let family = try sourceDecoder.container(keyedBy: FamilyKeys.self)
        if family.contains(.kind), try family.decode(String.self, forKey: .kind) == "word" {
            throw DecodingError.dataCorrupted(.init(codingPath: sourceDecoder.codingPath,
                debugDescription: "A placement factor cannot contain a word."))
        }
        let source = try AssemblyPlacement(from: sourceDecoder)
        switch try object.decode(String.self, forKey: .operation) {
        case "forward": self = .forward(source)
        case "inverse": self = .inverse(source)
        default: throw DecodingError.dataCorruptedError(forKey: .operation, in: object,
            debugDescription: "Unknown original placement operation.")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        switch self {
        case .forward(let source):
            try object.encode("forward", forKey: .operation); try object.encode(source, forKey: .placement)
        case .inverse(let source):
            try object.encode("inverse", forKey: .operation); try object.encode(source, forKey: .placement)
        }
    }
}
#endif
