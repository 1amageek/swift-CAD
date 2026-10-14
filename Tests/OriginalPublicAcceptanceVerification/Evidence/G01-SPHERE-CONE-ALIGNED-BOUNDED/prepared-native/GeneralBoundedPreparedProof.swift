import CADCore
import CADGeometry

@main struct GeneralBoundedPreparedProof {
    static func main() throws {
        let angle = Double(bitPattern: 0x3fddac670561bb50)
        let inputs: [(Point3D, Double, Point3D, Double)] = [
            (.origin, 2, .init(x: 3, y: 0, z: -4), angle),
            (.init(x: 1, y: -2, z: 0.5), 4, .init(x: 7, y: -2, z: -7.5), angle),
            (.origin, 2, .init(x: 3, y: 0, z: -4), 0.5)]
        for (center, radius, apex, angle) in inputs {
            for reversed in [false, true] {
                let sphere = Surface3D.analytic(.sphere(center: center, radius: radius))
                let cone = Surface3D.analytic(.cone(apex: apex, axis: .unitZ, halfAngle: angle))
                let counter = BoundedSphereConeSSIAcceptance.Counter()
                let session = try DefaultSurfaceSurfaceIntersector().prepareOriginalPair(
                    first: reversed ? cone : sphere, second: reversed ? sphere : cone,
                    tolerance: .standard, maximumSpanCount: 262_144, maximumSubdivisionDepth: 8,
                    remainingSourceDepth: 1, consumeWork: { try counter.consume() },
                    consumeStorage: { try counter.retain($0) }, maximumAlgebraicDepth: 32)
                let prepared = counter.totals.work
                let i = try ScalarInterval(lower: 0.25, upper: 0.75)
                let box = SurfaceParameterBox(u: i, v: i)
                let empty = try session.intersectionResult(firstBox: box, secondBox: box, options: .init())
                let r = try BoundedSphereConeSSIAcceptance.owner(empty)
                try BoundedSphereConeSSIAcceptance.require(r.source.original.criticalField.extensionLevel == 2)
                let again = try session.intersectionResult(firstBox: box, secondBox: box, options: .init())
                let e = try BoundedSphereConeSSIAcceptance.owner(again)
                try BoundedSphereConeSSIAcceptance.require(e.isEmpty && empty.intersections.isEmpty)
                var a = try BoundedSphereConeSSIAcceptance.ledger()
                try BoundedSphereConeSSIAcceptance.require(r.source.original.criticalField.compare(
                    r.source.original.lowerHalfAngle, e.source.original.lowerHalfAngle, using: &a) == .equal)
                try BoundedSphereConeSSIAcceptance.require(counter.totals.work - prepared < prepared)
                _ = try r.source.original.sectionValues(halfAngle: r.source.original.field.integer(1, using: &a), using: &a)
            }
        }
        print("PASS all new bounded inputs and both prepared orders: complete selected exclusion, retained two-level critical owner and source section")
    }
}
