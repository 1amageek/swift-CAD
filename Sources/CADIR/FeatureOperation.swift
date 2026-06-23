public enum FeatureOperation: Codable, Sendable {
    case sketch(Sketch)
    case extrude(ExtrudeFeature)
    case sweep(SweepFeature)
    case polySpline(PolySplineFeature)
    case faceLoopOffset(FaceLoopOffsetFeature)
    case edgeOffset(EdgeOffsetFeature)
    case faceKnife(FaceKnifeFeature)
    case bridgeCurve(BridgeCurveFeature)
    case curveEdit(CurveEditFeature)
    case curveOffset(CurveOffsetFeature)
    case curveTrim(CurveTrimFeature)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sketch
        case extrude
        case sweep
        case polySpline
        case faceLoopOffset
        case edgeOffset
        case faceKnife
        case bridgeCurve
        case curveEdit
        case curveOffset
        case curveTrim
    }

    private enum Kind: String, Codable {
        case sketch
        case extrude
        case sweep
        case polySpline
        case faceLoopOffset
        case edgeOffset
        case faceKnife
        case bridgeCurve
        case curveEdit
        case curveOffset
        case curveTrim
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .sketch:
            try container.validateOnlyExpectedKeys([.kind, .sketch], in: decoder)
            self = .sketch(try container.decode(Sketch.self, forKey: .sketch))
        case .extrude:
            try container.validateOnlyExpectedKeys([.kind, .extrude], in: decoder)
            self = .extrude(try container.decode(ExtrudeFeature.self, forKey: .extrude))
        case .sweep:
            try container.validateOnlyExpectedKeys([.kind, .sweep], in: decoder)
            self = .sweep(try container.decode(SweepFeature.self, forKey: .sweep))
        case .polySpline:
            try container.validateOnlyExpectedKeys([.kind, .polySpline], in: decoder)
            self = .polySpline(try container.decode(PolySplineFeature.self, forKey: .polySpline))
        case .faceLoopOffset:
            try container.validateOnlyExpectedKeys([.kind, .faceLoopOffset], in: decoder)
            self = .faceLoopOffset(try container.decode(FaceLoopOffsetFeature.self, forKey: .faceLoopOffset))
        case .edgeOffset:
            try container.validateOnlyExpectedKeys([.kind, .edgeOffset], in: decoder)
            self = .edgeOffset(try container.decode(EdgeOffsetFeature.self, forKey: .edgeOffset))
        case .faceKnife:
            try container.validateOnlyExpectedKeys([.kind, .faceKnife], in: decoder)
            self = .faceKnife(try container.decode(FaceKnifeFeature.self, forKey: .faceKnife))
        case .bridgeCurve:
            try container.validateOnlyExpectedKeys([.kind, .bridgeCurve], in: decoder)
            self = .bridgeCurve(try container.decode(BridgeCurveFeature.self, forKey: .bridgeCurve))
        case .curveEdit:
            try container.validateOnlyExpectedKeys([.kind, .curveEdit], in: decoder)
            self = .curveEdit(try container.decode(CurveEditFeature.self, forKey: .curveEdit))
        case .curveOffset:
            try container.validateOnlyExpectedKeys([.kind, .curveOffset], in: decoder)
            self = .curveOffset(try container.decode(CurveOffsetFeature.self, forKey: .curveOffset))
        case .curveTrim:
            try container.validateOnlyExpectedKeys([.kind, .curveTrim], in: decoder)
            self = .curveTrim(try container.decode(CurveTrimFeature.self, forKey: .curveTrim))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sketch(sketch):
            try container.encode(Kind.sketch, forKey: .kind)
            try container.encode(sketch, forKey: .sketch)
        case let .extrude(extrude):
            try container.encode(Kind.extrude, forKey: .kind)
            try container.encode(extrude, forKey: .extrude)
        case let .sweep(sweep):
            try container.encode(Kind.sweep, forKey: .kind)
            try container.encode(sweep, forKey: .sweep)
        case let .polySpline(polySpline):
            try container.encode(Kind.polySpline, forKey: .kind)
            try container.encode(polySpline, forKey: .polySpline)
        case let .faceLoopOffset(faceLoopOffset):
            try container.encode(Kind.faceLoopOffset, forKey: .kind)
            try container.encode(faceLoopOffset, forKey: .faceLoopOffset)
        case let .edgeOffset(edgeOffset):
            try container.encode(Kind.edgeOffset, forKey: .kind)
            try container.encode(edgeOffset, forKey: .edgeOffset)
        case let .faceKnife(faceKnife):
            try container.encode(Kind.faceKnife, forKey: .kind)
            try container.encode(faceKnife, forKey: .faceKnife)
        case let .bridgeCurve(bridgeCurve):
            try container.encode(Kind.bridgeCurve, forKey: .kind)
            try container.encode(bridgeCurve, forKey: .bridgeCurve)
        case let .curveEdit(curveEdit):
            try container.encode(Kind.curveEdit, forKey: .kind)
            try container.encode(curveEdit, forKey: .curveEdit)
        case let .curveOffset(curveOffset):
            try container.encode(Kind.curveOffset, forKey: .kind)
            try container.encode(curveOffset, forKey: .curveOffset)
        case let .curveTrim(curveTrim):
            try container.encode(Kind.curveTrim, forKey: .kind)
            try container.encode(curveTrim, forKey: .curveTrim)
        }
    }
}
