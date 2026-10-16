import CADCore
import WASILibc
@testable import CADGeometry

/// Locates concrete error boxing without changing the original refused query.
@main
struct EmbeddedGeometryFailureDiagnostic {
    static func log(_ value: String) { print(value); _ = fflush(nil) }
    static func kind(_ failure: ExactScalarFailure) -> String {
        switch failure {
        case .resourceLimit(.work): return "resourceLimit(work)"
        case .resourceLimit(.storage): return "resourceLimit(storage)"
        case .resourceLimit(.valueDepth): return "resourceLimit(valueDepth)"
        case .resourceLimit(.coefficientDepth): return "resourceLimit(coefficientDepth)"
        case .admissionRejected: return "admissionRejected"
        case .cancelled: return "cancelled"
        default: return "other scalar case"
        }
    }
    static func main() throws {
        let local: any Error = ExactScalarFailure.resourceLimit(.work)
        log(local is ExactScalarFailure ? "DIAG local scalar box recognized" : "DIAG local scalar box not recognized")
        let tolerance = ModelingTolerance(distance: 1e-10, angle: 1e-11, relative: 1e-12)
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [-2, -1, 0, 1, 2, 3, 4],
            vKnots: [0, 0, 1, 1], controlPoints: [0.0, 1.0].map { y in
                [-0.5, 0.5, 1.5, 2.5].map { Point3D(x: $0, y: y, z: 0) }
            })
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 2),
            v: try ScalarInterval(lower: 0, upper: 1))
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                maximumCells: 4096, remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumSpans: 64))
        do {
            _ = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: surface, over: box, tolerance: tolerance, maximumCellCount: 1, using: &execution)
            fatalError("The original refused query unexpectedly published panels.")
        } catch {
            if let scalar = error as? ExactScalarFailure { log("DIAG client scalar box: " + kind(scalar)) }
            else { log("DIAG client scalar box not recognized") }
            if let failure = OriginalQueryFailure.classification(of: error) {
                log("DIAG client original classification: " + failure.code.rawValue)
            } else { log("DIAG client original classification absent") }
            switch NativeExactGeometryPublicationFailure.resolve(error, tolerance: tolerance) {
            case .classified(let failure, _): log("DIAG library classification: " + failure.code.rawValue)
            case .retained(let failure): log("DIAG library retained classification: " + failure.kernelFailure.code.rawValue)
            case .cancelled: log("DIAG library cancellation")
            case .foreign: log("DIAG library foreign error")
            }
            log("DIAG original direct query refused; no geometry success was published")
        }
    }
}
