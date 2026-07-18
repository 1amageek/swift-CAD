import CADCore

public struct ThickenTargetReference: FeatureIDReference {
    public let featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}
