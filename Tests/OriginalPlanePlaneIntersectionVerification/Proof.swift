import CADCore

enum ProofFailure: Error { case incorrect(String) }

@main struct PlanePairProof {
    static func main() async throws {
        let tolerance = ModelingTolerance.standard
        let intersector = DefaultSurfaceSurfaceIntersector()
        let first = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        for separation in [tolerance.distance * 0.5, -tolerance.distance * 0.5, Double.leastNonzeroMagnitude, 2.0] {
            let second = Surface3D.analytic(.plane(origin: .init(x: 0, y: 0, z: separation), normal: -.unitZ))
            for reversed in [false, true] {
                let hits = try intersector.intersections(first: reversed ? second : first,
                    second: reversed ? first : second, tolerance: tolerance)
                guard hits.isEmpty else { throw ProofFailure.incorrect("Distinct parallel planes were not disjoint: \(separation)") }
            }
        }
        for normal in [Vector3D.unitZ, -Vector3D.unitZ] {
            let second = Surface3D.analytic(.plane(origin: .init(x: 0.5, y: -0.25, z: 0), normal: normal))
            let hits = try intersector.intersections(first: first, second: second, tolerance: tolerance)
            guard hits.count == 1, case .coincident(let coincidence) = hits[0], coincidence.residual == 0 else {
                throw ProofFailure.incorrect("Identical planes lost exact coincidence")
            }
        }
        for slope in [1.0, 0x1p-40] {
            let second = Surface3D.analytic(.plane(origin: .origin, normal: .init(x: slope, y: 0, z: slope == 1 ? 0 : 1)))
            for reversed in [false, true] {
                let hits = try intersector.intersections(first: reversed ? second : first,
                    second: reversed ? first : second, tolerance: tolerance)
                guard hits.count == 1, case .curve(let curve) = hits[0], case .line(let line) = curve.curve,
                    line.origin == .origin, abs(line.direction.y) == 1 else {
                    throw ProofFailure.incorrect("Nonparallel planes lost their intersection line")
                }
            }
        }
        let shiftedTilt = Surface3D.analytic(.plane(origin: .init(x: 0, y: 0, z: 1),
            normal: .init(x: 0x1p-40, y: 0, z: 1)))
        for reversed in [false, true] {
            let hits = try intersector.intersections(first: reversed ? shiftedTilt : first,
                second: reversed ? first : shiftedTilt, tolerance: tolerance)
            guard hits.count == 1, case .curve(let curve) = hits[0], case .line(let line) = curve.curve,
                line.origin.x == 0x1p40, line.origin.z == 0 else {
                throw ProofFailure.incorrect("Near-parallel planes with separated origins became empty")
            }
        }
        let offset = Surface3D.procedural(.offset(OffsetSurface3D(source: first, distance: 1)))
        let verticalOffset = Surface3D.procedural(.offset(OffsetSurface3D(
            source: .analytic(.plane(origin: .origin, normal: .unitX)), distance: 2)))
        let offsetHits = try intersector.intersections(first: offset, second: verticalOffset, tolerance: tolerance)
        guard offsetHits.count == 1, case .curve(let curve) = offsetHits[0], case .line(let line) = curve.curve,
            line.origin.x == 2, line.origin.z == 1 else {
            throw ProofFailure.incorrect("Existing transverse offset-plane publication changed")
        }
        do {
            _ = try intersector.intersections(first: first, second: offset, tolerance: tolerance)
            throw ProofFailure.incorrect("Unproved procedural plane equation became coincidence or absence")
        } catch let error as KernelError {
            guard error.code == .unsupportedCapability else { throw error }
        }
        do {
            let unrepresentable = Surface3D.analytic(.plane(origin: .origin,
                normal: .init(x: Double.leastNonzeroMagnitude, y: 0, z: 1)))
            _ = try intersector.intersections(first: first, second: unrepresentable, tolerance: tolerance)
            throw ProofFailure.incorrect("Unrepresentable transverse line became coincidence or absence")
        } catch let error as KernelError {
            guard error.code == .unsupportedCapability else { throw error }
        }
        do {
            _ = try intersector.intersections(first: first, second: first,
                options: .init(maximumSubdivisionCells: 1, maximumIterations: 1), tolerance: tolerance)
            throw ProofFailure.incorrect("Scalar resource exhaustion became success")
        } catch let error as KernelError {
            guard error.code == .resourceLimitExceeded else { throw error }
        }
        do {
            let scaled = Surface3D.analytic(.plane(origin: .origin, normal: .init(x: 0, y: 0, z: 2)))
            _ = try intersector.intersections(first: first, second: scaled, tolerance: tolerance)
            throw ProofFailure.incorrect("Legacy non-unit-normal admission changed")
        } catch let error as KernelError {
            guard error.code == .unsupportedCapability else { throw error }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try intersector.intersections(first: first, second: first, tolerance: tolerance)
                throw ProofFailure.incorrect("Cancelled plane classification became success")
            } catch is CancellationError { }
        }
        try await cancelled.value
        print("PASS actual SSI plane-pair separation/coincidence/near-angle/resource/normal/cancel")
    }
}
