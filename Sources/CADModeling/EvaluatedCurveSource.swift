import CADCore

/// Identifies whether an evaluated curve came from sketch IR or a modeling feature.
public enum EvaluatedCurveSource: Codable, Sendable, Hashable {
    case sketchEntity(SketchEntityID)
    case generatedFeature
}
