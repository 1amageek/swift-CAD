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
    case addCurveOffset(CADAgentAddCurveOffsetCommand)
    case addCurveTrim(CADAgentAddCurveTrimCommand)
    case addSelectionDimension(CADAgentAddSelectionDimensionCommand)

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
        case addCurveOffset
        case addCurveTrim
        case addSelectionDimension
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
        case addCurveOffset
        case addCurveTrim
        case addSelectionDimension
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
        case .addCurveOffset:
            try container.validateOnlyExpectedKeys([.kind, .addCurveOffset], in: decoder)
            self = .addCurveOffset(try container.decode(CADAgentAddCurveOffsetCommand.self, forKey: .addCurveOffset))
        case .addCurveTrim:
            try container.validateOnlyExpectedKeys([.kind, .addCurveTrim], in: decoder)
            self = .addCurveTrim(try container.decode(CADAgentAddCurveTrimCommand.self, forKey: .addCurveTrim))
        case .addSelectionDimension:
            try container.validateOnlyExpectedKeys([.kind, .addSelectionDimension], in: decoder)
            self = .addSelectionDimension(try container.decode(
                CADAgentAddSelectionDimensionCommand.self,
                forKey: .addSelectionDimension
            ))
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
        case let .addCurveOffset(command):
            try container.encode(Kind.addCurveOffset, forKey: .kind)
            try container.encode(command, forKey: .addCurveOffset)
        case let .addCurveTrim(command):
            try container.encode(Kind.addCurveTrim, forKey: .kind)
            try container.encode(command, forKey: .addCurveTrim)
        case let .addSelectionDimension(command):
            try container.encode(Kind.addSelectionDimension, forKey: .kind)
            try container.encode(command, forKey: .addSelectionDimension)
        }
    }
}
