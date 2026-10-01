import CADCore
import CADIR
import CADModeling

/// Bridge Surface's Short and Long walls: of two planar sheets, the one reaching less (Short) or
/// more (Long) far from where their planes meet, as the trimmed wall a `SheetBridgeFeature` names.
public struct SheetBridgeWallReach {
    public enum Wall: Sendable {
        case short
        case long
    }

    public init() {}

    /// Throws where the bridge itself would refuse the sheets: a sheet that is not one planar face,
    /// or planes that do not meet. Equal reaches take the first sheet.
    public func trimWalls(_ wall: Wall, first: FeatureID, second: FeatureID, reversesSense: Bool,
                          in document: EvaluatedDocument) throws -> SheetBridgeFeature.TrimWalls {
        let context = EvaluationContext(
            parameters: document.parameters,
            brep: document.brep,
            profiles: [:],
            curves: document.curves,
            subshapes: document.subshapes,
            lineage: document.lineage,
            tolerance: document.configuration.tolerance
        )
        let layout = try SheetBridgeLayout(first: first, second: second, reversesSense: reversesSense,
                                           featureID: FeatureID(), context: context)
        switch wall {
        case .short: return layout.first.reach <= layout.second.reach ? .first : .second
        case .long: return layout.first.reach >= layout.second.reach ? .first : .second
        }
    }
}
