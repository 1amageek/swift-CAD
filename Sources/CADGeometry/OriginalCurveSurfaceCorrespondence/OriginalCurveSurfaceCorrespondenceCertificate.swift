import CADCore

/// Immutable evidence minted only by the original-coefficient producer.
public struct OriginalCurveSurfaceCorrespondenceCertificate: Sendable {
    public let achievedUpperBound: Double
    public let consumedCellCount: Int
    public let sourceScalarCount: Int
    public let inspectedCells: Int
    private let curve: Curve3D
    private let startParameter: Double
    private let endParameter: Double
    private let surface: Surface3D
    private let parameterCurve: SurfaceParameterCurve
    private let options: CurveSurfaceCorrespondenceValidationOptions
    private let tolerance: ModelingTolerance

    init(curve: Curve3D, startParameter: Double, endParameter: Double,
         surface: Surface3D, parameterCurve: SurfaceParameterCurve,
         options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance,
         achievedUpperBound: Double, consumedCellCount: Int, sourceScalarCount: Int, inspectedCells: Int) {
        self.curve = curve
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.options = options
        self.tolerance = tolerance
        self.achievedUpperBound = achievedUpperBound
        self.consumedCellCount = consumedCellCount
        self.sourceScalarCount = sourceScalarCount
        self.inspectedCells = inspectedCells
    }

    public func validateBinding(
        curve: Curve3D, from startParameter: Double, to endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance
    ) throws {
        var budget = try OriginalCorrespondenceBudget(options: options, tolerance: tolerance)
        // The retained source data was already admitted by the producer under these options.
        // Check the small immutable header before scanning new source data; do not charge its
        // retained prefix a second time as though equality allocated another source owner.
        guard self.startParameter == startParameter, self.endParameter == endParameter,
              self.options == options, self.tolerance == tolerance else {
            throw OriginalCorrespondenceBudget.failure(.invalidInput, tolerance,
                "Original correspondence evidence has a foreign directed trim, tolerance or options.")
        }
        try budget.admitSources(curve: curve, surface: surface, parameterCurve: parameterCurve)
        guard self.curve == curve, self.startParameter == startParameter,
              self.endParameter == endParameter, self.surface == surface,
              self.parameterCurve == parameterCurve, self.options == options,
              self.tolerance == tolerance else {
            throw OriginalCorrespondenceBudget.failure(.invalidInput, tolerance,
                "Original correspondence evidence does not belong to these immutable sources and options.")
        }
    }
}
