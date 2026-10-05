import Foundation
import CADCore
import CADGeometry

/// The typed exact source stream is enclosed by its original drawing and paper law.
struct DrawingOriginalSilhouetteDescriptor: Encodable {
    let original: OriginalSilhouetteDrawingPath
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        let span = original.span
        try values.encode("original-silhouette-drawing-v1", forKey: .schema)
        try values.encode(span.bodyID, forKey: .bodyID); try values.encode(span.faceID, forKey: .faceID)
        try values.encode(span.componentOrdinal, forKey: .componentOrdinal); try values.encode(span.curveOrdinal, forKey: .curveOrdinal)
        try values.encode(span.isCoincidentWithTrim, forKey: .isCoincidentWithTrim)
        try values.encode(span.frame.origin, forKey: .origin); try values.encode(span.frame.horizontal, forKey: .horizontal)
        try values.encode(span.frame.vertical, forKey: .vertical); try values.encode(span.frame.normal, forKey: .normal)
        try values.encode(original.pointsPerMeter, forKey: .pointsPerMeter); try values.encode(original.translation, forKey: .translation)
        try values.encode(original.maximumDeviation, forKey: .maximumDeviationPaperPoints)
        try values.encode(original.maximumParameterWidth, forKey: .maximumParameterWidth)
    }
    private enum Keys: String, CodingKey {
        case schema, bodyID, faceID, componentOrdinal, curveOrdinal, isCoincidentWithTrim
        case origin, horizontal, vertical, normal, pointsPerMeter, translation
        case maximumDeviationPaperPoints, maximumParameterWidth
    }
    static func complete(_ original: OriginalSilhouetteDrawingPath, usage: inout DrawingExchangeUsage) throws -> String {
        var lower = original.silhouetteOwner
        guard original.admission.belongsToSameInvocation(as: usage, silhouetteUsage: lower) else {
            throw ExportError.invalidMesh("Original silhouette descriptor belongs to a different invocation.")
        }
        return try DrawingSilhouetteDescriptorEncoding.complete(Self(original: original), drawing: usage, lower: &lower,
            tolerance: original.span.curve.original.certificationTolerance) { sink, lower in
            try original.span.curve.writeOriginalProvenance(to: sink, usage: &lower)
        }
    }
}
