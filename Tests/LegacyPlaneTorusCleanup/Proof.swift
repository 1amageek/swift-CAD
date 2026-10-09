import CADCore
import CADGeometry
import LegacyPlaneTorus
import CleanPlaneTorus

enum ProofFailure: Error { case incorrect(String) }
@main struct CleanupProof {
    static func main() throws {
        let cases: [(String, Point3D, Vector3D, Int)] = [
            ("axial circles", .origin, .unitZ, 2),
            ("axial tangent", .init(x: 0, y: 0, z: 1), .unitZ, 1),
            ("axial empty", .init(x: 0, y: 0, z: 2), .unitZ, 0),
            ("meridional circles", .origin, .unitY, 2),
            ("support point", .init(x: 4, y: 0, z: 0), .unitX, 1),
            ("radial empty", .init(x: 5, y: 0, z: 0), .unitX, 0),
            ("general certified section", .init(x: 3, y: 0, z: 0), .unitX, 1)
        ]
        for (name, origin, normal, count) in cases {
            for reversed in [false, true] {
                let old = try LegacyPlaneTorus.planeTorus(origin: origin, normal: normal, reversed: reversed)
                let cleaned = try CleanPlaneTorus.planeTorus(origin: origin, normal: normal, reversed: reversed)
                guard old == cleaned, cleaned.count == count else { throw ProofFailure.incorrect(name) }
                if name == "axial circles" {
                    let radii = cleaned.compactMap { hit -> Double? in
                        guard case let .curve(result) = hit, case let .circle(circle) = result.curve else { return nil }
                        return circle.radius
                    }.sorted()
                    guard radii == [2, 4] else { throw ProofFailure.incorrect("axial geometry") }
                }
                if name == "support point" {
                    guard case let .point(point) = cleaned[0], point.point == origin else {
                        throw ProofFailure.incorrect("support geometry")
                    }
                }
                if name == "general certified section" {
                    guard case let .curve(curve) = cleaned[0], case .analytic(.planeTorus) = curve.curve,
                        curve.maximumResidual <= ModelingTolerance.standard.distance else {
                        throw ProofFailure.incorrect("certified general section")
                    }
                }
                print("PASS \(name) reversed=\(reversed)")
            }
        }
        for reversed in [false, true] {
            let invalid = SurfaceSurfaceIntersectionOptions(maximumIterations: 0)
            var before: KernelError?
            do {
                _ = try LegacyPlaneTorus.planeTorus(origin: .init(x: 3, y: 0, z: 0),
                    normal: .unitX, reversed: reversed, options: invalid)
                throw ProofFailure.incorrect("old invalid options succeeded")
            } catch let error as KernelError { before = error }
            do {
                _ = try CleanPlaneTorus.planeTorus(origin: .init(x: 3, y: 0, z: 0),
                    normal: .unitX, reversed: reversed, options: invalid)
                throw ProofFailure.incorrect("clean invalid options succeeded")
            } catch let error as KernelError {
                guard error == before, error.code == .resourceLimitExceeded else {
                    throw ProofFailure.incorrect("failure contract changed")
                }
            }
            print("PASS delegated resource failure reversed=\(reversed)")
        }
        print("LEGACY_PLANE_TORUS_CLEANUP_OK 14 successful comparisons and 2 explicit failure comparisons")
    }
}
