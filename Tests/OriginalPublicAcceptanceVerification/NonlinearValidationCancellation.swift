import CADCore
@testable import CADGeometry
import Synchronization

/// Cancels the actual task from the final bounded-validator work callback.
@main struct NonlinearValidationCancellation {
    static func validate(cancelAt: Int?) async throws -> Int {
        let count = Mutex(0)
        return try await Task {
            let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
                controlPoints:[[.origin,.origin],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
            let curve = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree:2,knots:[0,0,0,1,1,1],
                controlPoints:[.init(x:1,y:0),.init(x:-1,y:0),.init(x:1,y:0)]))
            try curve.validateOriginalSource(on:.bSpline(native),tolerance:.standard,
                remainingSourceDepth:4,maximumSubdivisionDepth:32,consumeWork:{ _ in
                    let n = count.withLock { value in value += 1; return value }
                    if n == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
                },maximumAlgebraicDepth:32)
            return count.withLock { $0 }
        }.value
    }
    static func main() async throws {
        let count = try await validate(cancelAt:nil)
        do {
            _ = try await validate(cancelAt:count)
            print("OBSERVED SUCCESS after final validator callback cancelled its task")
        } catch is CancellationError {
            print("PASS final validator callback task cancellation propagates")
        }
    }
}
