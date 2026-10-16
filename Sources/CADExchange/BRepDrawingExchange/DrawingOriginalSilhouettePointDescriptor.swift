import Foundation
import CADCore
import CADGeometry

/// Complete original point source, selector incidence and authored paper law.
struct DrawingOriginalSilhouettePointDescriptor: Encodable {
    let original: OriginalSilhouetteDrawingPoint
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode("original-silhouette-point-drawing-v1", forKey: .schema)
        try values.encode(original.bodyID, forKey: .bodyID); try values.encode(original.faceID, forKey: .faceID)
        try values.encode(original.original.frame.origin, forKey: .origin); try values.encode(original.original.frame.horizontal, forKey: .horizontal)
        try values.encode(original.original.frame.vertical, forKey: .vertical); try values.encode(original.original.frame.normal, forKey: .normal)
        try values.encode(original.pointsPerMeter, forKey: .pointsPerMeter); try values.encode(original.translation, forKey: .translation)
        try values.encode(original.maximumDeviation, forKey: .maximumDeviationPaperPoints)
        try values.encode(original.original.placement?.identity, forKey: .placementIdentity)
        let kind: String, index: Int
        switch original.selector {
        case .contact(let value): kind = "contact"; index = value
        case .algebraicContact(let value): kind = "algebraicContact"; index = value
        case .atlasStation(let value):
            kind = "atlasStation"; index = value
            try values.encode(original.original.atlasStations[value].atlasOrdinal, forKey: .atlasOrdinal)
            try values.encode(original.original.atlasStations[value].stationOrdinal, forKey: .stationOrdinal)
        case .singularStation(let value): kind = "singularStation"; index = value
        case .collapsedCurve(let value):
            kind = "collapsedCurve"; index = value
            let source = original.original.collapsedCurves[value]
            try values.encode(source.componentOrdinal, forKey: .componentOrdinal); try values.encode(source.curveOrdinal, forKey: .curveOrdinal)
            try values.encode(source.nativeRange, forKey: .nativeRange)
        }
        try values.encode(kind, forKey: .kind); try values.encode(index, forKey: .index)
    }
    private enum Keys: String, CodingKey {
        case schema, bodyID, faceID, origin, horizontal, vertical, normal, pointsPerMeter, translation
        case maximumDeviationPaperPoints, placementIdentity, kind, index, atlasOrdinal, stationOrdinal
        case componentOrdinal, curveOrdinal, nativeRange
    }
    static func complete(_ original: OriginalSilhouetteDrawingPoint, usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws -> String {
        let lower = original.silhouetteOwner
        guard original.admission.belongsToSameInvocation(as: usage, silhouetteContext: lower) else {
            throw ExportError.invalidMesh("Original silhouette point descriptor has a foreign invocation.")
        }
        return try DrawingSilhouetteDescriptorEncoding.complete(Self(original: original), drawing: usage, lower: lower,
            tolerance: original.original.configuration.tolerance, using: &execution) { sink, execution in
            try original.writeOriginalProvenance(to: sink, using: &execution)
        }
    }
}
