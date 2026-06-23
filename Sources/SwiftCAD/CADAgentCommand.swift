import CADCore
import CADIR

public enum CADAgentCommand: Codable, Sendable {
    case addSketch(CADAgentAddSketchCommand)
    case addExtrude(CADAgentAddExtrudeCommand)
    case addSweep(CADAgentAddSweepCommand)
    case addPolySpline(CADAgentAddPolySplineCommand)
    case addFaceLoopOffset(CADAgentAddFaceLoopOffsetCommand)
    case addEdgeOffset(CADAgentAddEdgeOffsetCommand)
    case addFaceKnife(CADAgentAddFaceKnifeCommand)
    case addBridgeCurve(CADAgentAddBridgeCurveCommand)
    case addCurveEdit(CADAgentAddCurveEditCommand)

    private enum CodingKeys: String, CodingKey {
        case kind
        case addSketch
        case addExtrude
        case addSweep
        case addPolySpline
        case addFaceLoopOffset
        case addEdgeOffset
        case addFaceKnife
        case addBridgeCurve
        case addCurveEdit
    }

    private enum Kind: String, Codable {
        case addSketch
        case addExtrude
        case addSweep
        case addPolySpline
        case addFaceLoopOffset
        case addEdgeOffset
        case addFaceKnife
        case addBridgeCurve
        case addCurveEdit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .addSketch:
            try container.validateOnlyExpectedKeys([.kind, .addSketch], in: decoder)
            self = .addSketch(try container.decode(CADAgentAddSketchCommand.self, forKey: .addSketch))
        case .addExtrude:
            try container.validateOnlyExpectedKeys([.kind, .addExtrude], in: decoder)
            self = .addExtrude(try container.decode(CADAgentAddExtrudeCommand.self, forKey: .addExtrude))
        case .addSweep:
            try container.validateOnlyExpectedKeys([.kind, .addSweep], in: decoder)
            self = .addSweep(try container.decode(CADAgentAddSweepCommand.self, forKey: .addSweep))
        case .addPolySpline:
            try container.validateOnlyExpectedKeys([.kind, .addPolySpline], in: decoder)
            self = .addPolySpline(try container.decode(CADAgentAddPolySplineCommand.self, forKey: .addPolySpline))
        case .addFaceLoopOffset:
            try container.validateOnlyExpectedKeys([.kind, .addFaceLoopOffset], in: decoder)
            self = .addFaceLoopOffset(try container.decode(CADAgentAddFaceLoopOffsetCommand.self, forKey: .addFaceLoopOffset))
        case .addEdgeOffset:
            try container.validateOnlyExpectedKeys([.kind, .addEdgeOffset], in: decoder)
            self = .addEdgeOffset(try container.decode(CADAgentAddEdgeOffsetCommand.self, forKey: .addEdgeOffset))
        case .addFaceKnife:
            try container.validateOnlyExpectedKeys([.kind, .addFaceKnife], in: decoder)
            self = .addFaceKnife(try container.decode(CADAgentAddFaceKnifeCommand.self, forKey: .addFaceKnife))
        case .addBridgeCurve:
            try container.validateOnlyExpectedKeys([.kind, .addBridgeCurve], in: decoder)
            self = .addBridgeCurve(try container.decode(CADAgentAddBridgeCurveCommand.self, forKey: .addBridgeCurve))
        case .addCurveEdit:
            try container.validateOnlyExpectedKeys([.kind, .addCurveEdit], in: decoder)
            self = .addCurveEdit(try container.decode(CADAgentAddCurveEditCommand.self, forKey: .addCurveEdit))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .addSketch(command):
            try container.encode(Kind.addSketch, forKey: .kind)
            try container.encode(command, forKey: .addSketch)
        case let .addExtrude(command):
            try container.encode(Kind.addExtrude, forKey: .kind)
            try container.encode(command, forKey: .addExtrude)
        case let .addSweep(command):
            try container.encode(Kind.addSweep, forKey: .kind)
            try container.encode(command, forKey: .addSweep)
        case let .addPolySpline(command):
            try container.encode(Kind.addPolySpline, forKey: .kind)
            try container.encode(command, forKey: .addPolySpline)
        case let .addFaceLoopOffset(command):
            try container.encode(Kind.addFaceLoopOffset, forKey: .kind)
            try container.encode(command, forKey: .addFaceLoopOffset)
        case let .addEdgeOffset(command):
            try container.encode(Kind.addEdgeOffset, forKey: .kind)
            try container.encode(command, forKey: .addEdgeOffset)
        case let .addFaceKnife(command):
            try container.encode(Kind.addFaceKnife, forKey: .kind)
            try container.encode(command, forKey: .addFaceKnife)
        case let .addBridgeCurve(command):
            try container.encode(Kind.addBridgeCurve, forKey: .kind)
            try container.encode(command, forKey: .addBridgeCurve)
        case let .addCurveEdit(command):
            try container.encode(Kind.addCurveEdit, forKey: .kind)
            try container.encode(command, forKey: .addCurveEdit)
        }
    }
}

public struct CADAgentAddSketchCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var sketch: Sketch

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case sketch
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, sketch: Sketch) {
        self.featureID = featureID
        self.name = name
        self.sketch = sketch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .sketch], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        sketch = try container.decode(Sketch.self, forKey: .sketch)
    }
}

public struct CADAgentAddExtrudeCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var extrude: ExtrudeFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case extrude
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, extrude: ExtrudeFeature) {
        self.featureID = featureID
        self.name = name
        self.extrude = extrude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .extrude], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        extrude = try container.decode(ExtrudeFeature.self, forKey: .extrude)
    }
}

public struct CADAgentAddSweepCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var sweep: SweepFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case sweep
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, sweep: SweepFeature) {
        self.featureID = featureID
        self.name = name
        self.sweep = sweep
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .sweep], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        sweep = try container.decode(SweepFeature.self, forKey: .sweep)
    }
}

public struct CADAgentAddPolySplineCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var polySpline: PolySplineFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case polySpline
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, polySpline: PolySplineFeature) {
        self.featureID = featureID
        self.name = name
        self.polySpline = polySpline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .polySpline], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        polySpline = try container.decode(PolySplineFeature.self, forKey: .polySpline)
    }
}

public struct CADAgentAddFaceLoopOffsetCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var faceLoopOffset: FaceLoopOffsetFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case faceLoopOffset
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, faceLoopOffset: FaceLoopOffsetFeature) {
        self.featureID = featureID
        self.name = name
        self.faceLoopOffset = faceLoopOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .faceLoopOffset], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        faceLoopOffset = try container.decode(FaceLoopOffsetFeature.self, forKey: .faceLoopOffset)
    }
}

public struct CADAgentAddEdgeOffsetCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var edgeOffset: EdgeOffsetFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case edgeOffset
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, edgeOffset: EdgeOffsetFeature) {
        self.featureID = featureID
        self.name = name
        self.edgeOffset = edgeOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .edgeOffset], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        edgeOffset = try container.decode(EdgeOffsetFeature.self, forKey: .edgeOffset)
    }
}

public struct CADAgentAddFaceKnifeCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var faceKnife: FaceKnifeFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case faceKnife
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, faceKnife: FaceKnifeFeature) {
        self.featureID = featureID
        self.name = name
        self.faceKnife = faceKnife
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .faceKnife], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        faceKnife = try container.decode(FaceKnifeFeature.self, forKey: .faceKnife)
    }
}

public struct CADAgentAddBridgeCurveCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var bridgeCurve: BridgeCurveFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case bridgeCurve
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, bridgeCurve: BridgeCurveFeature) {
        self.featureID = featureID
        self.name = name
        self.bridgeCurve = bridgeCurve
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .bridgeCurve], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        bridgeCurve = try container.decode(BridgeCurveFeature.self, forKey: .bridgeCurve)
    }
}

public struct CADAgentAddCurveEditCommand: Codable, Sendable {
    public var featureID: FeatureID?
    public var name: String?
    public var curveEdit: CurveEditFeature

    private enum CodingKeys: String, CodingKey {
        case featureID
        case name
        case curveEdit
    }

    public init(featureID: FeatureID? = nil, name: String? = nil, curveEdit: CurveEditFeature) {
        self.featureID = featureID
        self.name = name
        self.curveEdit = curveEdit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .name, .curveEdit], in: decoder)
        featureID = try container.decodeIfPresent(FeatureID.self, forKey: .featureID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        curveEdit = try container.decode(CurveEditFeature.self, forKey: .curveEdit)
    }
}

public struct CADAgentCommandResult: Sendable {
    public var document: CADDocument
    public var addedFeatureID: FeatureID

    public init(document: CADDocument, addedFeatureID: FeatureID) {
        self.document = document
        self.addedFeatureID = addedFeatureID
    }
}

public struct CADAgentCommandApplier: Sendable {
    public init() {}

    public func apply(
        _ command: CADAgentCommand,
        to document: CADDocument,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADAgentCommandResult {
        try document.validate(tolerance: tolerance)
        var updatedDocument = document
        let featureNode = try node(for: command, in: updatedDocument, tolerance: tolerance)
        guard updatedDocument.designGraph.nodes[featureNode.id] == nil else {
            throw FeatureEvaluationError.invalidGraph("Agent command feature ID already exists.")
        }
        updatedDocument.designGraph.nodes[featureNode.id] = featureNode
        updatedDocument.designGraph.order.append(featureNode.id)
        updatedDocument.designGraph.dependencies.append(contentsOf: dependencies(for: featureNode))
        updatedDocument.designGraph.revision = updatedDocument.designGraph.revision.advanced()
        try updatedDocument.validate(tolerance: tolerance)
        return CADAgentCommandResult(document: updatedDocument, addedFeatureID: featureNode.id)
    }

    private func node(
        for command: CADAgentCommand,
        in document: CADDocument,
        tolerance: ModelingTolerance
    ) throws -> FeatureNode {
        switch command {
        case let .addSketch(command):
            try command.sketch.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .sketch(command.sketch),
                outputs: [
                    FeatureOutput(role: .profile),
                    FeatureOutput(role: .curve),
                ]
            )
        case let .addExtrude(command):
            try validateProfileSource(command.extrude.profile, in: document)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .extrude(command.extrude),
                inputs: [FeatureInput(featureID: command.extrude.profile.featureID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addSweep(command):
            try command.sweep.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .sweep(command.sweep),
                inputs: sweepInputs(for: command.sweep),
                outputs: [FeatureOutput(role: sweepOutputRole(for: command.sweep.options.resultKind))]
            )
        case let .addPolySpline(command):
            try command.polySpline.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .polySpline(command.polySpline),
                outputs: [FeatureOutput(role: .sheet)]
            )
        case let .addFaceLoopOffset(command):
            try command.faceLoopOffset.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .faceLoopOffset(command.faceLoopOffset),
                inputs: [FeatureInput(featureID: command.faceLoopOffset.target.featureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addEdgeOffset(command):
            try command.edgeOffset.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .edgeOffset(command.edgeOffset),
                inputs: [FeatureInput(featureID: command.edgeOffset.target.featureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addFaceKnife(command):
            try command.faceKnife.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .faceKnife(command.faceKnife),
                inputs: [FeatureInput(featureID: command.faceKnife.target.featureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addBridgeCurve(command):
            try command.bridgeCurve.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .bridgeCurve(command.bridgeCurve),
                outputs: [FeatureOutput(role: .curve)]
            )
        case let .addCurveEdit(command):
            try command.curveEdit.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .curveEdit(command.curveEdit),
                inputs: [FeatureInput(featureID: command.curveEdit.source.featureID, role: .curve)],
                outputs: [FeatureOutput(role: .curve)]
            )
        }
    }

    private func validateProfileSource(_ profile: ProfileReference, in document: CADDocument) throws {
        try profile.validate()
        guard let source = document.designGraph.nodes[profile.featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw FeatureEvaluationError.invalidGraph("Agent extrude command profile source must declare a profile output.")
        }
    }

    private func sweepInputs(for sweep: SweepFeature) -> [FeatureInput] {
        sweep.profiles.map { profile in
            FeatureInput(featureID: profile.featureID, role: .profile)
        } + [
            FeatureInput(featureID: sweep.path.featureID, role: .path),
        ] + sweep.guides.map { guide in
            FeatureInput(featureID: guide.featureID, role: .guide)
        } + sweep.targets.map { target in
            FeatureInput(featureID: target.featureID, role: .target)
        }
    }

    private func dependencies(for node: FeatureNode) -> [DependencyEdge] {
        node.inputs.map { input in
            DependencyEdge(source: input.featureID, target: node.id)
        }
    }

    private func sweepOutputRole(for resultKind: SweepResultKind) -> FeaturePort {
        switch resultKind {
        case .solid:
            return .body
        case .sheet:
            return .sheet
        }
    }
}
