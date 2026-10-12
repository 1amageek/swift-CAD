import CADCore
@testable import CADGeometry
import Darwin

/// Observes ordinary SSI once; numerical success is separate from exact coverage.
@main struct CoonsPlaneSSIStop {
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints=0
        let cancelAt: Int?
        init(work: Int=300_000_000,bytes: Int=1_073_741_824,coefficient: Int=32,cancelAt: Int?=nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:coefficient));self.cancelAt=cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints==cancelAt { ledger.cancel() }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    static func main() throws { try observe() }

    nonisolated static func observe() throws {
        var admission = try Admission()
        // This is the existing multi-chart input from PolylineAtlasLiftProof.shape,
        // without constructing its unrelated boundary-corrected return value.
        let host = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            let stations = [0.0, 0.5, 1.0]
            let knots = [0.0, 0, 0.5, 1, 1]
            let native = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
                controlPoints: stations.map { v in stations.map { u in .init(x: u, y: v, z: 0) } })
            let issuer = OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of: .bSpline(native), at: side, maximumDepth: 0,
                    maximumSpanCount: 4, tolerance: .standard, usage: &usage)
            }
            return try OriginalCoonsSurface3D(vMinimumBoundary: boundary(.vLower),
                vMaximumBoundary: boundary(.vUpper), uMinimumBoundary: boundary(.uLower),
                uMaximumBoundary: boundary(.uUpper), tolerance: .standard, usage: &usage)
        }.value
        let first = Surface3D.procedural(.originalCoons(host))
        let second = Surface3D.plane(.init(origin: .init(x: 0.5, y: 0, z: 0), normal: .unitX))
        print("INPUT SSI-COONS-PLANE-01 original-four-chart-Coons full-square whole-plane-X=.5 stored-normal-unitX")
        print("ORACLE XYZ=(.5,V,0); CoonsUV=(.5,V); planeUV=(0,-V); 0<=V<=1; image=1 fiber=0")
        let mode = CommandLine.arguments.dropFirst().first ?? "bare"
        print("ENTRY", mode); fflush(nil)
        do {
            if mode == "bare" {
                let values = try DefaultSurfaceSurfaceIntersector().intersections(
                    first: first, second: second, options: .init(), tolerance: .standard)
                print("NUMERICAL_SUCCESS bare count", values.count)
                for value in values { print("VALUE", value) }
            } else {
                let value = try DefaultSurfaceSurfaceIntersector().intersectionResult(
                    first: first, second: second, options: .init(), tolerance: .standard)
                print("NUMERICAL_SUCCESS rich count", value.intersections.count)
                for item in value.intersections { print("VALUE", item) }
            }
        } catch let error as KernelError {
            print("OBSERVED_TYPED_FAILURE", mode, "KernelError", error.code, error.message)
        } catch let error as GeometryConversionError {
            print("OBSERVED_TYPED_FAILURE", mode, "GeometryConversionError", error)
        } catch {
            print("OBSERVED_OTHER_FAILURE", mode, error)
        }
    }
}
