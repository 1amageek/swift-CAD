import CADCore
import CADGeometry

/// The ordered parameter interval used by an edge on its canonical 3D curve.
public struct CurveTrim: Codable, Hashable, Sendable {
    public var startParameter: Double
    public var endParameter: Double

    public init(startParameter: Double, endParameter: Double) {
        self.startParameter = startParameter
        self.endParameter = endParameter
    }

    public func validate(on curve: Curve3D, edgeID: EdgeID, tolerance: ModelingTolerance) throws {
        try validateFiniteParameters(edgeID: edgeID, tolerance: tolerance)
        guard try curve.parameterDomain.containsSpan(
            from: startParameter,
            to: endParameter,
            tolerance: tolerance
        ) else {
            throw TopologyError.invalidTrim(edgeID)
        }
        let span = abs(endParameter - startParameter)
        switch curve {
        case .line:
            guard span > tolerance.distance else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case .circle:
            guard span > tolerance.angle,
                  span < (Double.pi * 2.0) - tolerance.angle else {
                throw TopologyError.invalidTrim(edgeID)
            }
        case let .analytic(curve):
            switch curve {
            case .line:
                guard span > tolerance.distance else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            case .circle, .ellipse:
                guard span > tolerance.angle,
                      span < (Double.pi * 2.0) - tolerance.angle else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            case .arc:
                guard span > tolerance.angle else {
                    throw TopologyError.invalidTrim(edgeID)
                }
            }
        case .bSpline:
            guard span > tolerance.distance else {
                throw TopologyError.invalidTrim(edgeID)
            }
        }
    }

    public func validateFiniteParameters(edgeID: EdgeID, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard startParameter.isFinite,
              endParameter.isFinite else {
            throw TopologyError.invalidTrim(edgeID)
        }
    }
}
