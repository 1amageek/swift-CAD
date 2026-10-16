import CADCore
import CADGeometry
import CADTopology

/// Directed authored boundary law, independent of a construction spline.
package struct OriginalFaceSectionSegment: Sendable {
    package let edgeID: EdgeID
    package let source: OriginalCurveSpanSource
    package let startParameter: Double
    package let endParameter: Double

    package init(edgeID: EdgeID, curve: Curve3D, startParameter: Double,
        endParameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        guard startParameter.isFinite, endParameter.isFinite,
              startParameter != endParameter,
              try curve.parameterDomain.containsSpan(from: startParameter,
                to: endParameter, tolerance: tolerance) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A face section boundary requires its original finite directed trim.")
        }
        self.edgeID = edgeID
        source = try OriginalCurveSpanSource(curve: curve, tolerance: tolerance, using: &execution)
        self.startParameter = startParameter
        self.endParameter = endParameter
    }

    private init(edgeID: EdgeID, source: OriginalCurveSpanSource,
        startParameter: Double, endParameter: Double) {
        self.edgeID = edgeID; self.source = source
        self.startParameter = startParameter; self.endParameter = endParameter
    }

    package func reversed() -> Self {
        Self(edgeID: edgeID, source: source,
            startParameter: endParameter, endParameter: startParameter)
    }
}
