import CADCore
import CADGeometry
import CADTopology

/// Patch from closed curves: a sheet spanning curves (sketch curves or edges of bodies through their
/// edge curves) that join end to end into one closed loop, or one closed curve.
public struct CurvePatchFeature: Hashable, Sendable {
    public var curves: [CurveSectionReference]

    public init(curves: [CurveSectionReference]) {
        self.curves = curves
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case curves
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curves], in: decoder)
        curves = try container.decode([CurveSectionReference].self, forKey: .curves)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curves, forKey: .curves)
    }
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard curves.isEmpty == false, (try OriginalParameterQueryStorage.set(try OriginalParameterQueryStorage.map(curves, using: &execution) { value, _ in value.featureID }, using: &execution)).count == curves.count else {
            throw FeatureEvaluationError.invalidGraph("A curve patch spans one or more distinct curves.")
        }
        for curve in curves {
            try execution.consumeWork(1)
            try curve.validate(using: &execution)
        }

        try execution.checkpoint()
    }

    func validationInputs(using execution: inout OriginalQueryExecution) throws -> [FeatureInput] {
        try execution.consumeWork(1)
        let result = try OriginalParameterQueryStorage.map(curves, using: &execution) { value, _ in
            FeatureInput(featureID: value.featureID, role: .curve)
        }
        try execution.checkpoint()
        return result
    }

    /// The features the patch consumes: its curves.
    public var inputs: [FeatureInput] {
        curves.map { FeatureInput(featureID: $0.featureID, role: .curve) }
    }
}

#if !hasFeature(Embedded)
extension CurvePatchFeature: Codable {}
#endif
