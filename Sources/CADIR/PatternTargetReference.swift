import CADCore

public struct PatternTargetReference: FeatureIDReference {
    public let featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}
