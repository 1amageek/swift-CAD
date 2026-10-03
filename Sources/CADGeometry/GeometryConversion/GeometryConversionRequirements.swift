import Foundation

public struct GeometryConversionRequirements: Sendable {
    public var maximumPositionError: Double
    public var maximumTangentAngle: Double
    public var maximumCurvatureError: Double
    public var maximumDegree: Int
    public var maximumControlPointCount: Int
    public var maximumCandidateCount: Int
    public var maximumCertificationBoxes: Int
    public var maximumScalarCount: Int
    public var maximumWorkUnits: Int

    public init(maximumPositionError: Double, maximumTangentAngle: Double, maximumCurvatureError: Double,
                maximumDegree: Int = 3, maximumControlPointCount: Int = 4_096,
                maximumCandidateCount: Int = 8, maximumCertificationBoxes: Int = 65_536,
                maximumScalarCount: Int = 1_048_576, maximumWorkUnits: Int = 16_777_216) {
        self.maximumPositionError = maximumPositionError
        self.maximumTangentAngle = maximumTangentAngle
        self.maximumCurvatureError = maximumCurvatureError
        self.maximumDegree = maximumDegree
        self.maximumControlPointCount = maximumControlPointCount
        self.maximumCandidateCount = maximumCandidateCount
        self.maximumCertificationBoxes = maximumCertificationBoxes
        self.maximumScalarCount = maximumScalarCount
        self.maximumWorkUnits = maximumWorkUnits
    }
    func validate() throws {
        guard maximumPositionError.isFinite, maximumPositionError > 0,
              maximumTangentAngle.isFinite, maximumTangentAngle > 0, maximumTangentAngle <= Double.pi,
              maximumCurvatureError.isFinite, maximumCurvatureError > 0,
              maximumDegree > 0, maximumControlPointCount > 0, maximumCandidateCount > 0,
              maximumCertificationBoxes > 0, maximumScalarCount > 0, maximumWorkUnits > 0 else {
            throw GeometryConversionError.invalidInput("Conversion requires finite positive allowances and positive budgets; tangent angle is at most pi.")
        }
    }
}
