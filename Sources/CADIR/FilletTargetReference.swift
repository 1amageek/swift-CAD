import CADCore

public struct FilletTargetReference: FeatureIDReference {
    public let featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}
