import CADCore
import CADGeometry

/// The original direct placement family of one assembly occurrence.
public enum AssemblyPlacement: Equatable, Sendable {
    case rigid(RigidTransform3D)
    case affine(AffineTransform3D)
    case step(OriginalSTEPPlacementSource)
    case word(AssemblyPlacementWord)

    public static func translated(by offset: Vector3D) -> Self { .rigid(.translated(by: offset)) }

    public func validate(tolerance: ModelingTolerance, maximumAlgebraicDepth: Int = 32, maximumSourceDepth: Int, consumeWork: @escaping () throws -> Void) throws {
        try consumeWork()
        guard (0...32).contains(maximumAlgebraicDepth), maximumSourceDepth > 0 else {
            throw AssemblyError.invalidSource("Original placement algebra depth must be in 0...32.")
        }
        switch self {
        case .rigid(let frame):
            try frame.validate(tolerance: tolerance)
            guard !frame.reversesOrientation else { throw AssemblyError.invalidPlacement }
        case .affine(let transform):
            _ = try transform.originalDeterminantSign(consumeWork: consumeWork)
        case .step(let source):
            var admission = AssemblyPlacementSourceAdmission(maximumDepth: maximumAlgebraicDepth, consume: consumeWork)
            try source.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth, usage: &admission)
        case .word(let word):
            for factor in word.factors { try factor.validate(tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth, maximumSourceDepth: maximumSourceDepth, consumeWork: consumeWork) }
        }
    }

    /// Exact coefficient identity; no tolerance or rounded inverse is involved.
    public var isExactIdentity: Bool {
        switch self {
        case .rigid(let frame):
            frame.basisX == .unitX && frame.basisY == .unitY && frame.basisZ == .unitZ && frame.translation == .zero
        case .affine(let frame):
            frame.basisX == .unitX && frame.basisY == .unitY && frame.basisZ == .unitZ && frame.translation == .zero
        case .word, .step: false
        }
    }

    public var affineTransform: AffineTransform3D {
        get throws {
            switch self {
            case .rigid(let value):
                return try AffineTransform3D(basisX: value.basisX, basisY: value.basisY,
                    basisZ: value.basisZ, translation: value.translation)
            case .affine(let value): return value
            case .step: throw AssemblyError.invalidSource("Original normalized STEP geometry cannot become rounded coefficient source.")
            case .word: throw AssemblyError.invalidSource("A placement word cannot be flattened into source coefficients.")
            }
        }
    }

    public func applying(to point: Point3D) throws -> Point3D {
        switch self { case .rigid(let frame): frame.applying(to: point)
        case .affine(let transform): transform.applying(to: point)
        case .word(let word): try word.applying(to: point)
        // FIXME(INCOMPLETE_IMPLEMENTATION): This legacy convenience lacks the
        // caller tolerance/depth/admission required by original normalized source.
        // Production assembly must use originalOperationWord and its bounded action.
        case .step: throw AssemblyError.unsupportedOriginalPlacementOperation }
    }
    public func applying(to vector: Vector3D) throws -> Vector3D {
        switch self { case .rigid(let frame): frame.applying(to: vector)
        case .affine(let transform): transform.applying(to: vector)
        case .word(let word): try word.applying(to: vector)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original normalized vector evaluation
        // requires the explicit caller admission supplied by the bounded word entry.
        case .step: throw AssemblyError.unsupportedOriginalPlacementOperation }
    }
}

#if !hasFeature(Embedded)
extension AssemblyPlacement: Codable {
    private enum Keys: String, CodingKey { case kind, transform, source, factors, basisX, basisY, basisZ, translation }
    private enum VectorKeys: String, CodingKey { case x, y, z }

    public init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: Keys.self)
        if object.contains(.kind) {
            let kind = try object.decode(String.self, forKey: .kind)
            switch kind {
            case "affine":
                try object.validateOnlyExpectedKeys([.kind, .transform], in: decoder)
                let transformDecoder = try object.superDecoder(forKey: .transform)
                try Self.validateFrameKeys(transformDecoder)
                self = .affine(try AffineTransform3D(from: transformDecoder))
            case "step":
                try object.validateOnlyExpectedKeys([.kind, .source], in: decoder)
                self = .step(try object.decode(OriginalSTEPPlacementSource.self, forKey: .source))
            case "word":
                try object.validateOnlyExpectedKeys([.kind, .factors], in: decoder)
                let factors = try object.decode([AssemblyPlacementFactor].self, forKey: .factors)
                self = .word(try AssemblyPlacementWord(factors: factors))
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: object,
                    debugDescription: "Unknown assembly placement family.")
            }
        } else {
            try Self.validateFrameKeys(decoder)
            self = .rigid(try RigidTransform3D(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .rigid(let frame): try frame.encode(to: encoder)
        case .affine(let transform):
            var object = encoder.container(keyedBy: Keys.self)
            try object.encode("affine", forKey: .kind)
            try object.encode(transform, forKey: .transform)
        case .step(let source):
            var object = encoder.container(keyedBy: Keys.self)
            try object.encode("step", forKey: .kind)
            try object.encode(source, forKey: .source)
        case .word(let word):
            var object = encoder.container(keyedBy: Keys.self)
            try object.encode("word", forKey: .kind)
            try object.encode(word.factors, forKey: .factors)
        }
    }

    private static func validateFrameKeys(_ decoder: Decoder) throws {
        let frame = try decoder.container(keyedBy: Keys.self)
        try frame.validateOnlyExpectedKeys([.basisX, .basisY, .basisZ, .translation], in: decoder)
        for key in [Keys.basisX, .basisY, .basisZ, .translation] {
            let vectorDecoder = try frame.superDecoder(forKey: key)
            let vector = try vectorDecoder.container(keyedBy: VectorKeys.self)
            try vector.validateOnlyExpectedKeys([.x, .y, .z], in: vectorDecoder)
        }
    }
}
#endif
