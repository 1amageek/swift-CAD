/// Producer-created evidence covering every point of one native parameter rectangle.
public struct NativeSurfacePositionCertificate: Equatable, Sendable {
    public let coveredParameters: SurfaceParameterBox
    public let positionErrorUpperBound: Double
    public let certifiedBoxCount: Int
    public let scalarCount: Int
    public let workUnits: Int

    init(coveredParameters: SurfaceParameterBox, positionErrorUpperBound: Double,
        certifiedBoxCount: Int, scalarCount: Int, workUnits: Int) {
        self.coveredParameters = coveredParameters
        self.positionErrorUpperBound = positionErrorUpperBound
        self.certifiedBoxCount = certifiedBoxCount
        self.scalarCount = scalarCount
        self.workUnits = workUnits
    }
}
