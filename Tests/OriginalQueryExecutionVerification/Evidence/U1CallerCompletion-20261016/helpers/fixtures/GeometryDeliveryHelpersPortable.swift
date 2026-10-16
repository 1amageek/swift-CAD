import CADCore
import CADGeometry
import Synchronization

/// Portable behavior of three delivery helpers; this is not intersection publication coverage.
@main
struct GeometryDeliveryHelpersPortable {
    struct Failure: Error { let line: Int; let detail: String }
    final class CancellationFlag: Sendable {
        private let state = Mutex(false)
        func cancel() { state.withLock { $0 = true } }
        func checkpoint() throws(ExactScalarFailure) {
            let shouldCancel = state.withLock { $0 }
            if shouldCancel { throw .cancelled }
        }
    }
    static let tolerance = ModelingTolerance.standard

    static func require(_ value: Bool, _ detail: String, line: Int = #line) throws {
        guard value else { throw Failure(line: line, detail: detail) }
    }
    static func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: sourceDepth))
    }
    static func originalFailure(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return originalFailure(retained.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let underlying) = scalar {
            return originalFailure(underlying)
        }
        return error
    }
    static func retainedFailure(_ error: any Error) -> OriginalQueryFailure? {
        if let retained = error as? OriginalQueryFailure { return retained }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let underlying) = scalar {
            return retainedFailure(underlying)
        }
        return nil
    }
    static func resourceRefusal(_ expected: ExactResource, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard let scalar = originalFailure(error) as? ExactScalarFailure,
                case .resourceLimit(let actual) = scalar, actual == expected else { throw error }
            return
        }
        throw Failure(line: #line, detail: "A resource-limited helper published output.")
    }
    static func cancellation(_ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard let scalar = originalFailure(error) as? ExactScalarFailure,
                case .cancelled = scalar else { throw error }
            return
        }
        throw Failure(line: #line, detail: "A cancelled helper published output.")
    }
    static func cancelledBudget() throws -> OriginalQueryBudget {
        let cancelled = CancellationFlag()
        let budget = try OriginalQueryBudget(checkpoint: { try cancelled.checkpoint() })
        cancelled.cancel()
        return budget
    }

    static func surface() -> BSplineSurface3D {
        // Literal heights of the Native sin(3*u+v)*0.4 control fixture avoid platform math imports.
        let heights: [UInt64] = [
            0x0000000000000000, 0x3fd58aaa0c073d8c, 0x3fd7472bef0e29d2,
            0x3face6c0af8aeef8, 0xbfd35fc7e4b0188c, 0xbfd88c67f7e6e0f6,
            0xbfbc9cb5aab4379a, 0x3fd0d1a09b8a6e6d, 0x3fd953dbb353d930,
            0x3fc519b82b3cf2db, 0xbfcbda97efebb21d, 0xbfd999892b587656,
            0xbfcb78f7f2f23c3c, 0x3fc58336a067d0d2, 0x3fd95c0b5b96b1d1,
            0x3fd0a5b9f4a568ba, 0xbfbd7b3673cb67f4
        ]
        let points = (0..<5).map { v in (0..<5).map { u in
            Point3D(x: Double(u), y: Double(v), z: Double(bitPattern: heights[u * 3 + v]))
        } }
        let weights = (0..<5).map { v in (0..<5).map { u in 1 + 0.25 * Double((u + v) % 3) } }
        return BSplineSurface3D(uDegree: 2, vDegree: 3,
            uKnots: [0, 0, 0, 0.4, 0.4, 1, 1, 1],
            vKnots: [0, 0, 0, 0, 0.5, 1, 1, 1, 1], controlPoints: points, weights: weights)
    }
    static func elevation() throws {
        for direction in [SurfaceParameterDirection.u, .v] {
            let source = surface()
            let ordinary = try source.elevatingDegree(direction: direction, tolerance: tolerance)
            let budget = try OriginalQueryBudget()
            var direct = try execution(budget)
            let raised = try source.elevatingDegree(direction: direction, tolerance: tolerance, using: &direct)
            try require(raised == ordinary, "Ordinary and direct elevation diverged.")
            switch direction {
            case .u:
                try require(raised.uDegree == 3 && raised.uControlPointCount == 7
                    && raised.uKnots == [0,0,0,0,0.4,0.4,0.4,1,1,1,1]
                    && raised.vKnots == source.vKnots, "The raised u basis changed continuity.")
            case .v:
                try require(raised.vDegree == 4 && raised.vControlPointCount == 7
                    && raised.vKnots == [0,0,0,0,0,0.5,0.5,1,1,1,1,1]
                    && raised.uKnots == source.uKnots, "The raised v basis changed continuity.")
            }
            try require(raised.weights.allSatisfy { $0.allSatisfy { $0 > 0 } }, "A raised weight is not positive.")
            // Source evaluation is independent of the elevation collocation algorithm.
            for i in 0...20 { for j in 0...20 {
                let u = Double(i) / 20, v = Double(j) / 20
                let before = try source.point(u: u, v: v, tolerance: tolerance)
                let after = try raised.point(u: u, v: v, tolerance: tolerance)
                try require((after - before).length < 1e-10, "Elevation changed the original rational surface.")
            } }
            let required = budget.snapshot
            try require(required.work > 0 && required.storageBytes > 0, "Elevation bypassed caller resources.")
            var scalar = ExactScalarLedger(limits: try .init(work: Int.max, storageBytes: Int.max,
                valueDepth: 32, coefficientDepth: 32))
            let scalarRaised = try source.elevatingDegree(direction: direction, tolerance: tolerance, using: &scalar)
            try require(scalarRaised == ordinary && scalar.work == required.work
                && scalar.storageBytes == required.storageBytes, "Generic scalar admission took a different body.")
            let exactBudget = try OriginalQueryBudget(workLimit: required.work, storageByteLimit: required.storageBytes)
            var exact = try execution(exactBudget)
            let exactRaised = try source.elevatingDegree(direction: direction, tolerance: tolerance, using: &exact)
            try require(exactRaised == ordinary && exactBudget.snapshot.work == required.work
                && exactBudget.snapshot.storageBytes == required.storageBytes, "Exact N elevation did not finish.")
            try resourceRefusal(.work) {
                _ = try source.elevatingDegree(direction: direction, tolerance: tolerance, using: &exact)
            }
            for resource in [ExactResource.work, .storage] {
                let limitedBudget = try OriginalQueryBudget(
                    workLimit: resource == .work ? required.work - 1 : required.work,
                    storageByteLimit: resource == .storage ? required.storageBytes - 1 : required.storageBytes)
                var limited = try execution(limitedBudget)
                try resourceRefusal(resource) {
                    _ = try source.elevatingDegree(direction: direction, tolerance: tolerance, using: &limited)
                }
            }
            let cancelled = try cancelledBudget()
            var stopped = try execution(cancelled)
            try cancellation { _ = try source.elevatingDegree(direction: direction, tolerance: tolerance, using: &stopped) }
            try require(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0,
                "Cancelled elevation debited resources.")
            print("USAGE Geometry delivery elevation work=\(required.work) bytes=\(required.storageBytes)")
        }
        print("PASS Geometry delivery degree elevation laws")
        print("PASS Geometry delivery degree elevation resources")
    }
    static func elevationRefusals() throws {
        let count = 513
        let knots = [0.0,0.0] + (1..<(count - 1)).map { Double($0) / Double(count - 1) } + [1.0,1.0]
        let row = (0..<count).map { Point3D(x: Double($0), y: 0, z: 0) }
        let dense = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: [0,0,1,1],
            controlPoints: [row, row.map { Point3D(x: $0.x, y: 1, z: 0) }])
        do { _ = try dense.elevatingDegree(direction: .u, tolerance: tolerance)
            throw Failure(line: #line, detail: "The existing 1,024 raised-control ceiling was bypassed.")
        } catch let error as GeometryError {
            guard case .invalidMatrixElementCount(1_025) = error else { throw error }
        }
        var unclamped = surface()
        unclamped.uKnots = [0,0.1,0.2,0.4,0.5,0.8,0.9,1]
        do { _ = try unclamped.elevatingDegree(direction: .u, tolerance: tolerance)
            throw Failure(line: #line, detail: "Unclamped elevation published output.")
        } catch let error as GeometryError {
            guard case .invalidDistance(2) = error else { throw error }
        }
    }

    static func retainedSource() throws -> (curve: Curve3D, plane: Surface3D, torus: Surface3D) {
        let normal = try Vector3D(x: 0.6, y: 0.2, z: 1).normalized(tolerance: tolerance.distance)
        let plane = Surface3D.analytic(.plane(origin: .origin, normal: normal))
        let torus = Surface3D.analytic(.torus(center: .origin, axis: .unitZ, majorRadius: 3, minorRadius: 1))
        let source = try CertifiedPlaneTorusIntersectionCurve(planeSurface: plane, torusSurface: torus,
            componentKind: .positiveFullBranch, lowerMinorAngle: 0, upperMinorAngle: 2 * Double.pi, tolerance: tolerance)
        return (.analytic(.planeTorus(source)), plane, torus)
    }
    static func supports() throws {
        // The construction scope has ended; the curve retains its authored supports.
        let retained = try retainedSource()
        try require(try retained.curve.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance) == retained.torus,
            "Ordinary lookup lost its retained plane host.")
        try require(try retained.curve.otherIntersectionSupportSurface(on: retained.torus, tolerance: tolerance) == retained.plane,
            "Ordinary lookup lost its retained torus host.")
        let normal = try Vector3D(x: 0.6, y: 0.2, z: 1).normalized(tolerance: tolerance.distance)
        let displacement = normal * (tolerance.distance / 2)
        let nearby = Surface3D.analytic(.plane(origin: .origin + displacement, normal: normal))
        try require(displacement.length > 0 && displacement.length < tolerance.distance,
            "The nearby plane must have a nonzero displacement within tolerance.")
        var direct = try execution(OriginalQueryBudget())
        try require(try retained.curve.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance, using: &direct) == retained.torus,
            "Direct lookup lost the retained support.")
        try require(try retained.curve.otherIntersectionSupportSurface(on: nearby, tolerance: tolerance, using: &direct) == nil,
            "Proximity became source host identity.")
        let parameterImage = Curve3D.parameterImage(try ParameterImageCurve3D(source: retained.curve, gain: 2, tolerance: tolerance))
        try require(try parameterImage.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance, using: &direct) == retained.torus,
            "Parameter image lost its support.")
        try require(direct.sourceDepth == 1, "Parameter image reset source depth.")
        guard case .analytic(.planeTorus(let source)) = retained.curve else {
            throw Failure(line: #line, detail: "The retained fixture lost its source kind.")
        }
        let exact = try CertifiedAnalyticAnalyticIntersectionCurve(planeTorusCurve: source,
            firstSurface: retained.plane, secondSurface: retained.torus, tolerance: tolerance)
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(intersection: exact, role: .first, tolerance: tolerance)
        let lift = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: retained.plane, parameterCurve: .certifiedAnalyticPair(pcurve)))
        try require(try lift.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance, using: &direct) == retained.torus,
            "A retained surface lift lost its other host.")
        let transform = RigidTransform3D.translated(by: Vector3D(x: 3, y: -2, z: 1))
        let image = Curve3D.rigidImage(try RigidImageCurve3D(source: retained.curve, transform: transform, tolerance: tolerance))
        let host = try transform.applying(to: retained.plane, tolerance: tolerance)
        let other = try transform.applying(to: retained.torus, tolerance: tolerance)
        var rigid = try execution(OriginalQueryBudget())
        try require(try image.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &rigid) == other,
            "Rigid transfer lost its exact authored host.")
        try require(rigid.sourceDepth == 1, "Rigid support transfer reset source depth.")
        var shallow = try execution(OriginalQueryBudget(), sourceDepth: 0)
        do { _ = try image.otherIntersectionSupportSurface(on: host, tolerance: tolerance, using: &shallow)
            throw Failure(line: #line, detail: "Source-depth exhaustion became nil or output.")
        } catch {
            guard let retained = retainedFailure(error) else { throw error }
            try require(retained.context.resource?.axis == .sourceDepth
                && retained.kernelFailure.code == .resourceLimitExceeded, "Wrong source-depth refusal.")
        }
        print("PASS Geometry delivery support ownership")
        let measured = try OriginalQueryBudget()
        var measuring = try execution(measured)
        try require(try retained.curve.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance, using: &measuring) == retained.torus,
            "Measured support lookup declined the exact host.")
        let required = measured.snapshot.work
        try require(required > 0, "Support lookup bypassed work admission.")
        let exactBudget = try OriginalQueryBudget(workLimit: required)
        var exactRead = try execution(exactBudget)
        try require(try retained.curve.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance, using: &exactRead) == retained.torus,
            "Exact N support lookup failed.")
        try require(exactBudget.snapshot.work == required, "Exact N support lookup changed its debit.")
        for budget in [try OriginalQueryBudget(workLimit: required - 1), exactBudget] {
            var limited = try execution(budget)
            try resourceRefusal(.work) {
                _ = try retained.curve.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance, using: &limited)
            }
        }
        let cancelled = try cancelledBudget()
        var stopped = try execution(cancelled)
        try cancellation { _ = try retained.curve.otherIntersectionSupportSurface(on: retained.plane, tolerance: tolerance, using: &stopped) }
        try require(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0, "Cancelled lookup debited resources.")
        print("USAGE Geometry delivery support work=\(required) bytes=\(measured.snapshot.storageBytes)")
        print("PASS Geometry delivery support resources")
    }
    final class NaturalCheckpoints: Sendable {
        private let state = Mutex(0)
        private let cancelAt: Int?
        init(cancelAt: Int? = nil) { self.cancelAt = cancelAt }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { value in value += 1; return value }
            if ordinal == cancelAt { throw .cancelled }
        }
    }
    static func naturalSource() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,0.5,1,1], vKnots: [0,0,1,1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.5, y: 0, z: 0), Point3D(x: 1, y: 0, z: 1)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 0.5, y: 1, z: 0), Point3D(x: 1, y: 1, z: 1)]],
            weights: [[2,2,2], [2,2,2]])
    }
    static func naturalExpected(_ u: Double, _ v: Double) -> Point3D {
        Point3D(x: u, y: v, z: u <= 0.5 ? 0 : 2 * u - 1)
    }
    static func retainedNatural(using execution: inout OriginalQueryExecution) throws -> BSplineSurfaceNaturalContinuation {
        var source = naturalSource()
        let result = try BSplineSurfaceNaturalContinuation(source, tolerance: tolerance, using: &execution)
        source.controlPoints[0][0].z = 99
        source.weights[1][2] = 7
        try require(source != naturalSource(), "The COW control did not mutate its caller input.")
        return result
    }
    static func naturalContinuation() throws {
        var direct = try execution(OriginalQueryBudget())
        let owner = try retainedNatural(using: &direct)
        let ordinary = try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance)
        for u in [-0.5,0,0.5,1,1.5] { for v in [-0.5,0,0.5,1,1.5] {
            let point = try owner.point(u: u, v: v, using: &direct)
            let ordinaryPoint = try ordinary.point(u: u, v: v)
            try require(point == naturalExpected(u, v) && ordinaryPoint == point,
                "Natural continuation changed its independent rational end-span law.")
        } }
        try require(direct.sourceDepth == 0, "A scalar natural read invented source depth.")
        print("PASS Geometry delivery natural continuation laws")
        let checkpoints = NaturalCheckpoints()
        let measured = try OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() })
        var measuring = try execution(measured)
        let measuredOwner = try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance, using: &measuring)
        let preparationCheckpoint = checkpoints.count
        let prepared = measured.snapshot
        _ = try measuredOwner.point(u: 1.5, v: -0.5, using: &measuring)
        let finalCheckpoint = checkpoints.count
        let complete = measured.snapshot
        try require(prepared.work > 0 && prepared.storageBytes > 0
            && complete.work > prepared.work && complete.storageBytes > prepared.storageBytes,
            "Cold natural preparation or reading bypassed caller resources.")
        let exactBudget = try OriginalQueryBudget(workLimit: complete.work, storageByteLimit: complete.storageBytes)
        var exact = try execution(exactBudget)
        let exactOwner = try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance, using: &exact)
        let exactPoint = try exactOwner.point(u: 1.5, v: -0.5, using: &exact)
        try require(exactPoint == naturalExpected(1.5, -0.5)
            && exactBudget.snapshot.work == complete.work && exactBudget.snapshot.storageBytes == complete.storageBytes,
            "Cold exact N natural continuation failed or changed debit.")
        for resource in [ExactResource.work, .storage] {
            let preparationBudget = try OriginalQueryBudget(workLimit: resource == .work ? prepared.work - 1 : nil,
                storageByteLimit: resource == .storage ? prepared.storageBytes - 1 : nil)
            var preparationRead = try execution(preparationBudget)
            try resourceRefusal(resource) {
                _ = try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance, using: &preparationRead)
            }
            let readBudget = try OriginalQueryBudget(workLimit: resource == .work ? complete.work - 1 : nil,
                storageByteLimit: resource == .storage ? complete.storageBytes - 1 : nil)
            var read = try execution(readBudget)
            let readOwner = try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance, using: &read)
            try require(readBudget.snapshot.work == prepared.work && readBudget.snapshot.storageBytes == prepared.storageBytes,
                "Cold N minus one must permit natural preparation before refusing its read.")
            try resourceRefusal(resource) { _ = try readOwner.point(u: 1.5, v: -0.5, using: &read) }
        }
        let cumulative = try OriginalQueryBudget(workLimit: complete.work)
        var first = try execution(cumulative)
        let retained = try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance, using: &first)
        _ = try retained.point(u: 1.5, v: -0.5, using: &first)
        try resourceRefusal(.work) { _ = try retained.point(u: 1.5, v: -0.5) }
        try require(cumulative.snapshot.work == complete.work, "Ordinary natural read reset the retained budget.")
        let beforeForeign = cumulative.snapshot
        let foreignBudget = try OriginalQueryBudget()
        var foreign = try execution(foreignBudget)
        let foreignPoint = try retained.point(u: 1.5, v: -0.5, using: &foreign)
        try require(foreignPoint == naturalExpected(1.5, -0.5)
            && foreignBudget.snapshot.work > 0 && foreignBudget.snapshot.storageBytes > 0
            && cumulative.snapshot.work == beforeForeign.work && cumulative.snapshot.storageBytes == beforeForeign.storageBytes,
            "Foreign natural reader failed to use its caller authority.")
        print("USAGE Geometry delivery natural work=\(complete.work) bytes=\(complete.storageBytes)")
        print("PASS Geometry delivery natural continuation resources")
        for stop in [1, preparationCheckpoint, finalCheckpoint] {
            let counter = NaturalCheckpoints(cancelAt: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try counter.checkpoint() })
            var stopped = try execution(budget)
            try cancellation {
                let stoppedOwner = try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance, using: &stopped)
                _ = try stoppedOwner.point(u: 1.5, v: -0.5, using: &stopped)
            }
            let work = stop == 1 ? 0 : (stop == preparationCheckpoint ? prepared.work : complete.work)
            let bytes = stop == 1 ? 0 : (stop == preparationCheckpoint ? prepared.storageBytes : complete.storageBytes)
            try require(budget.snapshot.work == work && budget.snapshot.storageBytes == bytes,
                "Terminal natural cancellation changed the admitted debit.")
        }
        let cancelled = try cancelledBudget()
        var stopped = try execution(cancelled)
        try cancellation { _ = try owner.point(u: 0.5, v: 0.5, using: &stopped) }
        try require(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0,
            "Entry-cancelled natural read debited resources.")
        let contributedBudget = try OriginalQueryBudget()
        var preparing = try execution(contributedBudget)
        let contribution = try preparing.makeContributionHandle()
        let contributed = try preparing.withContributionScope(contribution) { execution in
            try BSplineSurfaceNaturalContinuation(naturalSource(), tolerance: tolerance, using: &execution)
        }
        var shallow = try execution(contributedBudget, sourceDepth: 0)
        try require(preparing.activeContributionCount == 0 && shallow.activeContributionCount == 0,
            "The retained contribution control began with a warm reader.")
        let before = contributedBudget.snapshot
        do {
            _ = try shallow.withSourceDepthOffset(1) { execution in
                try contributed.point(u: 0.5, v: 0.5, using: &execution)
            }
            throw Failure(line: #line, detail: "Mapped natural source-depth exhaustion published output.")
        } catch {
            guard let failure = retainedFailure(error) else { throw error }
            try require(failure.context.resource?.axis == .sourceDepth
                && failure.kernelFailure.code == .resourceLimitExceeded, "Wrong natural depth refusal.")
        }
        try require(contributedBudget.snapshot.work == before.work
            && contributedBudget.snapshot.storageBytes == before.storageBytes && shallow.activeContributionCount == 0,
            "Natural depth refusal reattached and charged a retained contribution first.")
        print("PASS Geometry delivery natural continuation lifecycle")
    }
    static func main() throws {
        do {
            try elevation()
            try elevationRefusals()
            try supports()
            try naturalContinuation()
            print("PASS Geometry delivery helpers all")
        } catch {
            if let failure = error as? Failure {
                print("FAIL Geometry delivery helper line=\(failure.line) detail=\(failure.detail)")
            } else if let failure = retainedFailure(error) {
                print("FAIL Geometry delivery helper original code=\(failure.kernelFailure.code.rawValue) message=\(failure.kernelFailure.message)")
            } else {
                print("FAIL Geometry delivery helper unexpected typed cause; rethrowing unchanged")
            }
            throw error
        }
    }
}
