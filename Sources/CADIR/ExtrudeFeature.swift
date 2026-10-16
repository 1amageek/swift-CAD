import CADCore
import CADGeometry
import CADTopology

public struct ExtrudeFeature: Sendable, Hashable {
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
    /// The source-frame pull direction; nil uses the extrusion axis.
    public var draftDirection: Vector3D?
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
        draftDirection: Vector3D? = nil,
        thickness: CADExpression? = nil
    ) {
        self.init(section: .profile(profile), distance: distance, startDistance: startDistance, direction: direction,
                  operation: operation, targets: targets, keepTools: keepTools, resultKind: resultKind, draftAngle: draftAngle,
                  draftDirection: draftDirection, thickness: thickness)
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
        draftDirection: Vector3D? = nil,
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
        self.draftDirection = draftDirection
        self.thickness = thickness
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case section
        case distance
        case startDistance
        case direction
        case operation
        case targets, keepTools
        case resultKind
        case draftAngle
        case draftDirection
        case thickness
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.section, .distance, .startDistance, .direction, .operation, .targets, .keepTools, .resultKind, .draftAngle, .draftDirection, .thickness],
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
        draftDirection = try container.decodeIfPresent(Vector3D.self, forKey: .draftDirection)
        thickness = try container.decodeIfPresent(CADExpression.self, forKey: .thickness)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
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
        try container.encodeIfPresent(draftDirection, forKey: .draftDirection)
        try container.encodeIfPresent(thickness, forKey: .thickness)
    }
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try section.validate(using: &execution)
        if operation == .newBody {
            guard targets.isEmpty, !keepTools else {
                throw FeatureEvaluationError.invalidGraph("New-body extrusion cannot declare Boolean targets or Keep Tools.")
            }
        } else {
            guard resultKind == .solid, !targets.isEmpty,
                  (try OriginalParameterQueryStorage.set(try OriginalParameterQueryStorage.map(targets, using: &execution) { value, _ in value.featureID }, using: &execution)).count == targets.count,
                  try section.isFace || !(try OriginalParameterQueryStorage.contains(targets, using: &execution,
                    predicate: { value, _ in value.featureID == section.featureID })) else {
                // A face section may combine with the body it lies on; a profile or a curve's source
                // is no body to combine with.
                throw FeatureEvaluationError.invalidGraph("Boolean extrusion requires solid output and unique targets distinct from its section.")
            }
            for value in targets {
                try execution.consumeWork(1)
                try value.validate(using: &execution)
            }
        }
        try distance.validateDocumentLiteralQuantities(using: &execution)
        try startDistance?.validateDocumentLiteralQuantities(using: &execution)
        try draftAngle?.validateDocumentLiteralQuantities(using: &execution)
        if let draftDirection {
            try execution.consumeWork(1); try draftDirection.validate()
            guard draftDirection.length.isFinite, draftDirection.length > 0 else {
                throw FeatureEvaluationError.invalidGraph("Extrusion draft pull direction must be finite and nonzero.")
            }
        }
        try thickness?.validateDocumentLiteralQuantities(using: &execution)
        guard thickness == nil || resultKind == .solid else {
            throw FeatureEvaluationError.invalidGraph("A thin extrusion makes a solid wall.")
        }
        guard direction != .symmetric || startDistance == nil else {
            throw FeatureEvaluationError.invalidGraph("Symmetric extrusion cannot also specify a start position.")
        }
        guard resultKind == .sheet || section.isClosedRegion || thickness != nil else {
            throw FeatureEvaluationError.invalidGraph("A curve extrusion requires sheet output, or a thickness to make a solid wall.")
        }
        if case .vector(let vector) = direction {
            try execution.consumeWork(1)
            try vector.validate()
        }

        try execution.checkpoint()
    }

    /// Resolves signed axial endpoints once for geometry, measurement and editing.
    public func resolvedAxialRange(
        tolerance: ModelingTolerance,
        resolve: (CADExpression) throws -> Quantity
    ) throws -> ClosedRange<Double> {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try resolvedAxialRange(tolerance: tolerance, using: &execution,
            resolve: { expression, _ in try resolve(expression) })
    }

    public func resolvedAxialRange(
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        resolve: (CADExpression, inout OriginalQueryExecution) throws -> Quantity
    ) throws -> ClosedRange<Double> {
        try execution.consumeWork(1)
        try validate(using: &execution)
        try tolerance.validate()
        func length(_ expression: CADExpression) throws -> Double {
            try execution.consumeWork(1)
            let quantity = try resolve(expression, &execution)
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
            try execution.checkpoint()
            return (-end / 2)...(end / 2)
        }
        let start = try startDistance.map(length) ?? 0
        let span = abs(end - start)
        guard span.isFinite, span > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(span)
        }
        try execution.checkpoint()
        return min(start, end)...max(start, end)
    }
}

/// Which body a linear extrusion builds.
///
/// A solid extrusion caps both ends of the swept wall; a sheet extrusion leaves them open and
/// sews the wall alone. The profile is the same value in both cases, so the choice belongs to the
/// feature rather than to the profile it consumes. Open curves produce sheets only.
public enum ExtrudeResultKind: String, Sendable, Hashable {
    case solid
    case sheet
}

public enum SolidOperation: String, Sendable, Hashable {
    case newBody, union, difference, intersect, slice
}

public enum ExtrudeDirection: Sendable, Hashable {
    case normal
    case vector(Vector3D)
    case symmetric

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case vector
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case normal
        case vector
        case symmetric
    }
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
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
#endif
}

#if !hasFeature(Embedded)
extension ExtrudeFeature: Codable {}
extension ExtrudeResultKind: Codable {}
extension SolidOperation: Codable {}
extension ExtrudeDirection: Codable {}
#endif
