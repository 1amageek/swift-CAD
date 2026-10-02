import CADCore
import CADGeometry
import CADIR

/// Fills a closed non-planar loop of curves (in order, each running along it) with one smooth sheet
/// trimmed by it, within a stated deviation: what Patch asks of a loop with more than four corners,
/// which no exact Coons patch spans without creases. CADKernel provides it (XNURBS's fit).
package protocol CurveLoopFilling: Sendable {
    func fill(loop: [BSplineCurve3D], feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult
}
