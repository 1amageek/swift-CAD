import CADCore
import WASILibc
@testable import CADGeometry

/// Checks one real refusal against historical modules without priming error metadata.
@main
struct EmbeddedHistoricalClassificationControl {
    enum OracleFailure: Error { case unexpectedSuccess, incorrectRefusal }

    nonisolated static func run() throws {
        let tolerance = ModelingTolerance(distance: 1e-10, angle: 1e-11, relative: 1e-12)
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [-2, -1, 0, 1, 2, 3, 4], vKnots: [0, 0, 1, 1],
            controlPoints: [
                [Point3D(x: -0.5, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0),
                 Point3D(x: 1.5, y: 0, z: 0), Point3D(x: 2.5, y: 0, z: 0)],
                [Point3D(x: -0.5, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0),
                 Point3D(x: 1.5, y: 1, z: 0), Point3D(x: 2.5, y: 1, z: 0)]
            ])
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 2),
            v: try ScalarInterval(lower: 0, upper: 1))
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                maximumCells: 4096, remainingSourceDepth: 16,
                maximumSubdivisionDepth: 32, maximumSpans: 64))
        do {
            _ = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: surface, over: box, tolerance: tolerance, maximumCellCount: 1, using: &execution)
        } catch {
            guard let scalar = error as? ExactScalarFailure,
                case .admissionRejected(let cause) = scalar,
                let failure = cause as? OriginalQueryFailure,
                failure.kernelFailure.code == .resourceLimitExceeded,
                failure.context.resource?.axis == .work,
                let original = failure.originalError as? ExactScalarFailure,
                case .resourceLimit(.work) = original else {
                Swift.print("FAIL historical real refusal lost its scalar cause, classification, or work axis")
                _ = fflush(nil)
                throw error
            }
            Swift.print("PASS historical module-only control: real admissionRejected retains resourceLimit(work), kernel resourceLimitExceeded, and work axis")
            _ = fflush(nil)
            return
        }
        throw OracleFailure.unexpectedSuccess
    }

    static func main() throws { try run() }
}
