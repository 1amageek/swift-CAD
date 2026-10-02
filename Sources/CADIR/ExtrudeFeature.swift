import CADCore

public struct ExtrudeFeature: Codable, Sendable, Hashable {
    public var section: SectionReference
    public var distance: CADExpression
    public var startDistance: CADExpression?
    public var direction: ExtrudeDirection
    public var operation: SolidOperation
    public var targets: [BooleanTargetReference]
    public var keepTools: Bool
    public var resultKind: ExtrudeResultKind
    /// The walls' draft: a positive angle narrows the section along the extrusion direction, one
    /// taper running straight through the sketch plane; nil or zero leaves the walls straight.
    public var draftAngle: CADExpression?
    /// A thin extrusion's wall thickness: every loop of the section becomes a wall of it on the
    /// material's side, open at both ends — a curve's sheet thickened toward the curve's left about
    /// the extrusion direction (inside a counterclockwise closed curve); nil extrudes the whole
    /// section.
    public var thickness: CADExpression?

    public init(
        profile: ProfileReference,
        distance: CADExpression,
        startDistance: CADExpression? = nil,
        direction: ExtrudeDirection = .normal,
        operation: SolidOperation = .newBody,
        targets: [BooleanTargetReference] = [],
        keepTools: Bool = false,
        resultKind: ExtrudeResultKind = .solid,
        draftAngle: CADExpression? = nil,
        thickness: CADExpression? = nil
    ) {
        self.init(section: .profile(profile), distance: distance, startDistance: startDistance, direction: direction,
                  operation: operation, targets: targets, keepTools: keepTools, resultKind: resultKind, draftAngle: draftAngle,
                  thickness: thickness)
    }

    public init(
        section: SectionReference,
        distance: CADExpression,
        startDistance: CADExpression? = nil,
        direction: ExtrudeDirection = .normal,
        operation: SolidOperation = .newBody,
        targets: [BooleanTargetReference] = [],
        keepTools: Bool = false,
        resultKind: ExtrudeResultKind,
        draftAngle: CADExpression? = nil,
        thickness: CADExpression? = nil
    ) {
        self.section = section
        self.distance = distance
        self.startDistance = startDistance
        self.direction = direction
        self.operation = operation
        self.targets = targets
        self.keepTools = keepTools
        self.resultKind = resultKind
        self.draftAngle = draftAngle
        self.thickness = thickness
    }

    private enum CodingKeys: String, CodingKey {
        case section
        case distance
        case startDistance
        case direction
        case operation
        case targets, keepTools
        case resultKind
        case draftAngle
        case thickness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.section, .distance, .startDistance, .direction, .operation, .targets, .keepTools, .resultKind, .draftAngle, .thickness],
            in: decoder
        )
        section = try container.decode(SectionReference.self, forKey: .section)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        startDistance = try container.decodeIfPresent(CADExpression.self, forKey: .startDistance)
        direction = try container.decode(ExtrudeDirection.self, forKey: .direction)
        operation = try container.decode(SolidOperation.self, forKey: .operation)
        targets = try container.decodeIfPresent([BooleanTargetReference].self, forKey: .targets) ?? []
        keepTools = try container.decodeIfPresent(Bool.self, forKey: .keepTools) ?? false
        resultKind = try container.decode(ExtrudeResultKind.self, forKey: .resultKind)
        draftAngle = try container.decodeIfPresent(CADExpression.self, forKey: .draftAngle)
        thickness = try container.decodeIfPresent(CADExpression.self, forKey: .thickness)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section, forKey: .section)
        try container.encode(distance, forKey: .distance)
        try container.encodeIfPresent(startDistance, forKey: .startDistance)
        try container.encode(direction, forKey: .direction)
        try container.encode(operation, forKey: .operation)
        if !targets.isEmpty { try container.encode(targets, forKey: .targets) }
        if keepTools { try container.encode(keepTools, forKey: .keepTools) }
        try container.encode(resultKind, forKey: .resultKind)
        try container.encodeIfPresent(draftAngle, forKey: .draftAngle)
        try container.encodeIfPresent(thickness, forKey: .thickness)
    }

    public func validate() throws {
        try section.validate()
        if operation == .newBody {
            guard targets.isEmpty, !keepTools else {
                throw FeatureEvaluationError.invalidGraph("New-body extrusion cannot declare Boolean targets or Keep Tools.")
            }
        } else {
            guard resultKind == .solid, !targets.isEmpty,
                  Set(targets.map(\.featureID)).count == targets.count,
                  section.isFace || !targets.contains(where: { $0.featureID == section.featureID }) else {
                // A face section may combine with the body it lies on; a profile or a curve's source
                // is no body to combine with.
                throw FeatureEvaluationError.invalidGraph("Boolean extrusion requires solid output and unique targets distinct from its section.")
            }
            try targets.forEach { try $0.validate() }
        }
        try distance.validateLiteralQuantities()
        try startDistance?.validateLiteralQuantities()
        try draftAngle?.validateLiteralQuantities()
        try thickness?.validateLiteralQuantities()
        guard thickness == nil || resultKind == .solid else {
            throw FeatureEvaluationError.invalidGraph("A thin extrusion makes a solid wall.")
        }
        guard direction != .symmetric || startDistance == nil else {
            throw FeatureEvaluationError.invalidGraph("Symmetric extrusion cannot also specify a start position.")
        }
        guard resultKind == .sheet || section.isClosedRegion || thickness != nil else {
            throw FeatureEvaluationError.invalidGraph("A curve extrusion requires sheet output, or a thickness to make a solid wall.")
        }
        if case .vector(let vector) = direction { try vector.validate() }
    }

    /// Resolves signed axial endpoints once for geometry, measurement and editing.
    public func resolvedAxialRange(
        tolerance: ModelingTolerance,
        resolve: (CADExpression) throws -> Quantity
    ) throws -> ClosedRange<Double> {
        try validate()
        try tolerance.validate()
        func length(_ expression: CADExpression) throws -> Double {
            let quantity = try resolve(expression)
            guard quantity.kind == .length else {
                throw UnitError.expectedQuantity(operation: "extrude.extent", expected: .length, actual: quantity.kind)
            }
            guard quantity.value.isFinite else {
                throw FeatureEvaluationError.invalidDistance(quantity.value)
            }
            return quantity.value
        }
        let end = try length(distance)
        if direction == .symmetric {
            guard end > tolerance.distance else { throw FeatureEvaluationError.invalidDistance(end) }
            return (-end / 2)...(end / 2)
        }
        let start = try startDistance.map(length) ?? 0
        let span = abs(end - start)
        guard span.isFinite, span > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(span)
        }
        return min(start, end)...max(start, end)
    }
}

/// Which body a linear extrusion builds.
///
/// A solid extrusion caps both ends of the swept wall; a sheet extrusion leaves them open and
/// sews the wall alone. The profile is the same value in both cases, so the choice belongs to the
/// feature rather than to the profile it consumes. Open curves produce sheets only.
public enum ExtrudeResultKind: String, Codable, Sendable, Hashable {
    case solid
    case sheet
}

public enum SolidOperation: String, Codable, Sendable, Hashable {
    case newBody, union, difference, intersect, slice
}

public enum ExtrudeDirection: Codable, Sendable, Hashable {
    case normal
    case vector(Vector3D)
    case symmetric

    private enum CodingKeys: String, CodingKey {
        case kind
        case vector
    }

    private enum Kind: String, Codable {
        case normal
        case vector
        case symmetric
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .normal:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .normal
        case .vector:
            try container.validateOnlyExpectedKeys([.kind, .vector], in: decoder)
            self = .vector(try container.decode(Vector3D.self, forKey: .vector))
        case .symmetric:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .symmetric
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .normal:
            try container.encode(Kind.normal, forKey: .kind)
        case let .vector(vector):
            try container.encode(Kind.vector, forKey: .kind)
            try container.encode(vector, forKey: .vector)
        case .symmetric:
            try container.encode(Kind.symmetric, forKey: .kind)
        }
    }
}
