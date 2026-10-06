import CADCore

public struct SketchPointSelectionReference: Hashable, Sendable {
    public var featureID: FeatureID
    public var entityID: SketchEntityID

    public init(featureID: FeatureID, entityID: SketchEntityID) {
        self.featureID = featureID
        self.entityID = entityID
    }

    public func validate() throws {}
}

#if !hasFeature(Embedded)
extension SketchPointSelectionReference: Codable {}
#endif
