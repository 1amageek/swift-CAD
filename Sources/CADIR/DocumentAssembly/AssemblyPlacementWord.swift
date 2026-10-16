import CADCore
import CADGeometry

/// Original parent-to-child factors; application visits the word in reverse order.
public struct AssemblyPlacementWord: Equatable, Sendable {
    public let factors: [AssemblyPlacementFactor]

    public init(factors: [AssemblyPlacementFactor]) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(factors: factors, using: &execution)
    }
    public init(factors: [AssemblyPlacementFactor], using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard !factors.isEmpty else { throw AssemblyError.invalidSource("An assembly placement word cannot be empty.") }
        for factor in factors {
            try execution.consumeWork(1)
            if case .word = factor.originalPlacement { throw AssemblyError.invalidSource("Assembly placement words require direct factors.") }
        }
        self.factors = factors
    }
    public init(placement: RigidTransform3D) { factors = [.forward(.rigid(placement))] }

    public func applying(to point: Point3D) throws -> Point3D {
        var result = point
        for factor in factors.reversed() { result = try factor.applying(to: result) }
        return result
    }
    public func applying(to vector: Vector3D) throws -> Vector3D {
        var result = vector
        for factor in factors.reversed() { result = try factor.applying(to: result) }
        return result
    }
}

#if !hasFeature(Embedded)
extension AssemblyPlacementWord: Codable {
    private enum Keys: String, CodingKey { case factors }
    public init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: Keys.self)
        if object.contains(.factors) {
            try object.validateOnlyExpectedKeys([.factors], in: decoder)
            try self.init(factors: object.decode([AssemblyPlacementFactor].self, forKey: .factors))
        } else {
            // Old rigid artifact frames retain their single original factor.
            let frame = try AssemblyPlacement(from: decoder)
            guard case .rigid = frame else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "A legacy assembly placement word must be a rigid frame."))
            }
            try self.init(factors: [.forward(frame)])
        }
    }
    public func encode(to encoder: Encoder) throws {
        if factors.count == 1, case .forward(.rigid(let frame)) = factors[0] { try frame.encode(to: encoder) }
        else {
            var object = encoder.container(keyedBy: Keys.self)
            try object.encode(factors, forKey: .factors)
        }
    }
}
#endif
