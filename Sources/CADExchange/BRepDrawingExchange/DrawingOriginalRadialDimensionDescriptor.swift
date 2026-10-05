import CADCore
import CADGeometry

/// Raw original law and paper placement; display enclosures are not encoded as source.
struct DrawingOriginalRadialDimensionDescriptor: Encodable {
    let source: Curve3D
    let boundaryParameter: Double
    let placement: OriginalAffineOperationWord?
    let effectiveOperationWord: OriginalAffineOperationWord
    let tolerance: ModelingTolerance
    let bodyID: BodyID?
    let sourceFeatureID: FeatureID?
    let sourceSketchEntityID: SketchEntityID?
    let occurrenceIdentity: String?
    let measurementIdentity: String
    let identity: String
    let kind: DrawingRadialDimensionKind
    let frameOrigin: Point3D
    let frameHorizontal: Vector3D
    let frameVertical: Vector3D
    let frameNormal: Vector3D
    let pointsPerMeter: Double
    let translation: Point2D

    init(_ source: DrawingRadialDimensionSource) {
        self.source = source.original.source; boundaryParameter = source.original.boundaryParameter
        placement = source.original.placement; effectiveOperationWord = source.original.effectiveOperationWord
        tolerance = source.original.tolerance; bodyID = source.bodyID
        sourceFeatureID = source.sourceFeatureID; sourceSketchEntityID = source.sourceSketchEntityID
        occurrenceIdentity = source.occurrenceIdentity
        measurementIdentity = source.measurementIdentity; identity = source.identity; kind = source.kind
        frameOrigin = source.frame.origin; frameHorizontal = source.frame.horizontal
        frameVertical = source.frame.vertical; frameNormal = source.frame.normal
        pointsPerMeter = source.pointsPerMeter; translation = source.translation
    }
    private enum CodingKeys: String, CodingKey {
        case source, boundaryParameter, placement, effectiveOperationWord, tolerance, bodyID
        case sourceFeatureID, sourceSketchEntityID
        case occurrenceIdentity, measurementIdentity, identity, kind, frameOrigin, frameHorizontal
        case frameVertical, frameNormal, pointsPerMeter, translation
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source, forKey: .source)
        try values.encode(boundaryParameter, forKey: .boundaryParameter)
        try values.encode(placement, forKey: .placement)
        try values.encode(effectiveOperationWord, forKey: .effectiveOperationWord)
        try values.encode(tolerance, forKey: .tolerance)
        try values.encode(bodyID, forKey: .bodyID)
        try values.encode(sourceFeatureID, forKey: .sourceFeatureID)
        try values.encode(sourceSketchEntityID, forKey: .sourceSketchEntityID)
        try values.encode(occurrenceIdentity, forKey: .occurrenceIdentity)
        try values.encode(measurementIdentity, forKey: .measurementIdentity)
        try values.encode(identity, forKey: .identity)
        try values.encode(kind, forKey: .kind)
        try values.encode(frameOrigin, forKey: .frameOrigin)
        try values.encode(frameHorizontal, forKey: .frameHorizontal)
        try values.encode(frameVertical, forKey: .frameVertical)
        try values.encode(frameNormal, forKey: .frameNormal)
        try values.encode(pointsPerMeter, forKey: .pointsPerMeter)
        try values.encode(translation, forKey: .translation)
    }

}
