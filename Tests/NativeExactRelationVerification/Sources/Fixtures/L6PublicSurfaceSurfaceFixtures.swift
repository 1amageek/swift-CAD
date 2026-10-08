import CADCore
@testable import CADGeometry
import Synchronization

public enum L6PublicSurfaceSurfaceFixtures {
    private enum Route: String, CaseIterable { case ordinary, admitted, domains, prepared }
    private enum Rejection: Error { case work, storage }

    private final class Allowance: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0; var storageCalls = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let cancellingStorageCall: Int?
        init(work: Int = 80_000_000, bytes: Int = 1_073_741_824, cancellingStorageCall: Int? = nil) {
            maximumWork = work; maximumBytes = bytes; self.cancellingStorageCall = cancellingStorageCall
        }
        var counts: State { state.withLock { $0 } }
        func work() throws {
            try state.withLock { value in
                guard value.work < maximumWork else { throw Rejection.work }
                value.work += 1
            }
        }
        func storage(_ bytes: Int) throws {
            let cancel = try state.withLock { value in
                guard bytes >= 0, bytes <= maximumBytes - value.bytes else { throw Rejection.storage }
                value.bytes += bytes; value.storageCalls += 1
                return value.storageCalls == cancellingStorageCall
            }
            if cancel { throw CancellationError() }
        }
    }

    private static func box(_ surface: BSplineSurface3D) throws -> SurfaceParameterBox {
        .init(u: try .init(lower: surface.uKnots[surface.uDegree], upper: surface.uKnots[surface.uControlPointCount]),
            v: try .init(lower: surface.vKnots[surface.vDegree], upper: surface.vKnots[surface.vControlPointCount]))
    }

    private static func rich(_ route: Route, _ first: BSplineSurface3D, _ second: BSplineSurface3D,
        firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
        options: SurfaceSurfaceIntersectionOptions = .init(), allowance: Allowance = .init(),
        sourceDepth: Int = 1, algebraicDepth: Int = 32
    ) throws -> SurfaceSurfaceIntersectionResult {
        let solver: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        switch route {
        case .ordinary:
            return try solver.intersectionResult(first: .bSpline(first), second: .bSpline(second),
                options: options, tolerance: .standard)
        case .admitted:
            return try solver.intersectionResult(first: .bSpline(first), second: .bSpline(second),
                options: options, tolerance: .standard, maximumSpanCount: 1,
                maximumSubdivisionDepth: 0, remainingSourceDepth: sourceDepth,
                consumeWork: { try allowance.work() }, consumeStorage: { try allowance.storage($0) },
                maximumAlgebraicDepth: algebraicDepth)
        case .domains:
            return try solver.intersectionResult(first: .bSpline(first), over: firstBox ?? box(first),
                second: .bSpline(second), over: secondBox ?? box(second), options: options, tolerance: .standard,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: sourceDepth,
                consumeWork: { try allowance.work() }, consumeStorage: { try allowance.storage($0) },
                maximumAlgebraicDepth: algebraicDepth)
        case .prepared:
            let pair = try solver.prepareOriginalPair(first: .bSpline(first), second: .bSpline(second),
                tolerance: .standard, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
                remainingSourceDepth: sourceDepth, consumeWork: { try allowance.work() },
                consumeStorage: { try allowance.storage($0) }, maximumAlgebraicDepth: algebraicDepth)
            return try pair.intersectionResult(firstBox: firstBox ?? box(first),
                secondBox: secondBox ?? box(second), options: options)
        }
    }

    private static func discrete(_ route: Route, _ first: BSplineSurface3D, _ second: BSplineSurface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(), allowance: Allowance = .init()
    ) throws -> [SurfaceSurfaceIntersection] {
        let solver: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        switch route {
        case .ordinary:
            return try solver.intersections(first: .bSpline(first), second: .bSpline(second),
                options: options, tolerance: .standard)
        case .admitted:
            return try solver.intersections(first: .bSpline(first), second: .bSpline(second),
                options: options, tolerance: .standard, maximumSpanCount: 1,
                maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: { try allowance.work() }, consumeStorage: { try allowance.storage($0) },
                maximumAlgebraicDepth: 32)
        case .domains:
            return try solver.intersections(first: .bSpline(first), over: box(first),
                second: .bSpline(second), over: box(second), options: options, tolerance: .standard,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: { try allowance.work() }, consumeStorage: { try allowance.storage($0) },
                maximumAlgebraicDepth: 32)
        case .prepared:
            let pair = try solver.prepareOriginalPair(first: .bSpline(first), second: .bSpline(second),
                tolerance: .standard, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
                remainingSourceDepth: 1, consumeWork: { try allowance.work() },
                consumeStorage: { try allowance.storage($0) }, maximumAlgebraicDepth: 32)
            return try pair.intersections(firstBox: box(first), secondBox: box(second), options: options)
        }
    }

    private static func authority(_ result: SurfaceSurfaceIntersectionResult) throws -> NativeExactGeometricRelation {
        guard let exact = result.originalExactGeometricRelation,
            result.originalNativePoints == nil, result.originalNativeRelations == nil else {
            throw NativeExactFixtures.Failure.invalidEvidence
        }
        return exact
    }

    public static func verifyClosedEndpoints() throws {
        let first = NativeExactFixtures.plane()
        let second = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
                [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 1)],
                [.init(x: 0,y: 1,z: 1), .init(x: 1,y: 1,z: 2)]])
        for route in Route.allCases {
            let result = try rich(route, first, second)
            let exact = try authority(result)
            guard result.intersections.count == 1, case .point(let point) = result.intersections[0] else {
                throw NativeExactFixtures.Failure.invalidEvidence
            }
            try NativeExactFixtures.require(point.point == .origin
                && point.firstSurfaceParameter.u == 0 && point.firstSurfaceParameter.v == 0
                && point.secondSurfaceParameter.u == 0 && point.secondSurfaceParameter.v == 0
                && point.residual <= ModelingTolerance.standard.distance
                && !exact.hasPositiveDimensionalSolutions)
            var query = try NativeExactFixtures.ledger()
            try NativeExactFixtures.member([(0,1), (0,1), (0,1), (0,1)],
                exact.parameterRelation, expected: true, &query)
            try NativeExactFixtures.member([(1,2), (1,2), (1,2), (1,2)],
                exact.parameterRelation, expected: false, &query)
            print("PASS migrated SSI \(route.rawValue) closed endpoint preserves exact XYZ and all UV")
        }
    }

    public static func verifyRoutes() throws {
        try verifyClosedEndpoints()
        for route in Route.allCases {
            let first = NativeExactFixtures.plane()
            var second = L6SurfaceSurfaceFixtures.tangency()
            let allowance = Allowance()
            let result = try rich(route, first, second, allowance: allowance)
            let exact = try authority(result)
            guard result.intersections.count == 1, case .point(let point) = result.intersections[0] else {
                throw NativeExactFixtures.Failure.invalidEvidence
            }
            let sourcePoint = try first.point(u: point.firstSurfaceParameter.u,
                v: point.firstSurfaceParameter.v, tolerance: .standard)
            let targetPoint = try second.point(u: point.secondSurfaceParameter.u,
                v: point.secondSurfaceParameter.v, tolerance: .standard)
            try NativeExactFixtures.require(!exact.hasPositiveDimensionalSolutions
                && !exact.hasPositiveDimensionalImage && exact.geometry.evidenceKind == .isolatedParameters
                && (sourcePoint - targetPoint).length <= point.residual)
            let numerical = try discrete(route, first, second)
            try NativeExactFixtures.require(numerical == result.intersections)
            second.controlPoints.removeAll()
            guard case .surfaceSurface(let retainedFirst, let retainedSecond, _, _) = exact.parameterRelation.source else {
                throw NativeExactFixtures.Failure.invalidEvidence
            }
            try NativeExactFixtures.require(retainedFirst == first && retainedSecond.controlPoints.count == 3)
            var query = try NativeExactFixtures.ledger()
            try NativeExactFixtures.member([(1, 3), (2, 3), (1, 3), (2, 3)],
                exact.parameterRelation, expected: true, &query)
            if route != .ordinary {
                try NativeExactFixtures.require(allowance.counts.work > 0 && allowance.counts.bytes > 0)
            }
            print("PASS migrated SSI rich/discrete \(route.rawValue) and retained original UV work=\(allowance.counts.work)")
        }
    }

    public static func verifyCoverage() throws {
        try verifyCoverageRoutes()
        try verifyCoverageFibers()
    }

    public static func verifyCoverageRoutes(only: String? = nil) throws {
        let plane = NativeExactFixtures.plane()
        for route in Route.allCases where only == nil || only == route.rawValue {
            for mode in 0..<4 {
                let first = mode == 3 ? L6SurfaceSurfaceFixtures.collapsed() : plane
                let second = mode == 0 ? L6SurfaceSurfaceFixtures.perpendicular()
                    : NativeExactFixtures.plane(z: mode == 2 ? 1 : 0)
                let result = try rich(route, first, second)
                let exact = try authority(result)
                try NativeExactFixtures.require(result.intersections.isEmpty)
                if mode == 2 {
                    try NativeExactFixtures.require(exact.geometry.isEmpty && !exact.hasPositiveDimensionalSolutions)
                    try NativeExactFixtures.require(try discrete(route, first, second).isEmpty)
                } else {
                    let image = mode == 0 ? 1 : mode == 1 ? 2 : 0
                    try NativeExactFixtures.require(exact.hasPositiveDimensionalSolutions
                        && exact.geometry.strata.contains { $0.imageDimension == image })
                    do {
                        _ = try discrete(route, first, second)
                        throw NativeExactFixtures.Failure.invalidEvidence
                    } catch let error as KernelError {
                        try NativeExactFixtures.require(error.code == .nonDiscreteIntersection)
                    }
                }
            }
            print("PASS migrated SSI \(route.rawValue) curve/region/empty/collapsed coverage")
        }
    }

    public static func verifyCoverageFibers(only: String? = nil) throws {
        let plane = NativeExactFixtures.plane()
        let selected = SurfaceParameterBox(u: try .init(lower: 0.25, upper: 1), v: try .init(lower: 0, upper: 1))
        for route in [Route.domains, .prepared] where only == nil || only == route.rawValue {
            let result = try rich(route, L6SurfaceSurfaceFixtures.folded(), plane, secondBox: selected)
            let exact = try authority(result)
            try NativeExactFixtures.require(exact.parameterRelation.relation.components.count == 2)
            var query = try NativeExactFixtures.ledger()
            try NativeExactFixtures.member([(-1, 2), (1, 2), (1, 4), (1, 2)], exact.parameterRelation, expected: true, &query)
            try NativeExactFixtures.member([(1, 2), (1, 2), (1, 4), (1, 2)], exact.parameterRelation, expected: true, &query)
            let xyz = try L6SurfaceSurfaceFixtures.xyz(0.25, 0.5, 0, in: exact, using: &query)
            let fiber = try L6SurfaceSurfaceFixtures.Resolver(cells: L6SurfaceSurfaceFixtures.Cells.self,
                topology: .init(cells: L6SurfaceSurfaceFixtures.Cells.self)).fiber(at: .xyz(xyz), in: exact.geometry,
                    limits: L6SurfaceSurfaceFixtures.limits(), using: &query)
            try NativeExactFixtures.require(fiber.components.count == 2)
            print("PASS migrated SSI \(route.rawValue) two source branches and exact fiber")
        }
    }

    public static func verifyFailures() throws {
        let first = NativeExactFixtures.plane(), second = L6SurfaceSurfaceFixtures.tangency()
        // Z = u^2 - 1/2 has an irrational section inside the closed unit box.
        // Unlike the linear cuts of the rational tangency, it needs root refinement.
        let nonlinear = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0,0,0,1,1,1], vKnots: [0,0,1,1], controlPoints: [
                [.init(x: 0,y: 0,z: -0.5), .init(x: 0.5,y: 0,z: -0.5), .init(x: 1,y: 0,z: 0.5)],
                [.init(x: 0,y: 1,z: -0.5), .init(x: 0.5,y: 1,z: -0.5), .init(x: 1,y: 1,z: 0.5)]])
        let baseline = try rich(.admitted, first, nonlinear)
        try NativeExactFixtures.require(try authority(baseline).hasPositiveDimensionalSolutions)
        for route in [Route.admitted, .domains, .prepared] {
            let exactWithoutRefinement = try rich(route, first, second, algebraicDepth: 0)
            try NativeExactFixtures.require(exactWithoutRefinement.intersections.count == 1)
            for storage in [false, true] {
                let short = Allowance(work: storage ? 80_000_000 : 0, bytes: storage ? 0 : 1_073_741_824)
                do {
                    _ = try rich(route, first, second, allowance: short)
                    throw NativeExactFixtures.Failure.invalidEvidence
                } catch let cause as Rejection {
                    switch cause {
                    case .work: try NativeExactFixtures.require(!storage)
                    case .storage: try NativeExactFixtures.require(storage)
                    }
                }
            }
            for mode in 0..<3 {
                do {
                    _ = try rich(route, first, mode == 2 ? nonlinear : second,
                        options: .init(maximumSubdivisionCells: mode == 0 ? 1 : 262_144),
                        sourceDepth: mode == 1 ? 0 : 1, algebraicDepth: mode == 2 ? 0 : 32)
                    throw NativeExactFixtures.Failure.invalidEvidence
                } catch let error as KernelError {
                    try NativeExactFixtures.require(error.code == .resourceLimitExceeded)
                }
            }
            print("PASS migrated SSI \(route.rawValue) original caller causes and independent cell/source/depth limits")
        }
        for empty in [false, true] {
            let second = empty ? NativeExactFixtures.plane(z: 1) : second
            let measured = Allowance()
            _ = try rich(.admitted, first, second, allowance: measured)
            let cancelled = Allowance(cancellingStorageCall: measured.counts.storageCalls)
            do {
                _ = try rich(.admitted, first, second, allowance: cancelled)
                throw NativeExactFixtures.Failure.invalidEvidence
            } catch is CancellationError { }
            try NativeExactFixtures.require(cancelled.counts.storageCalls == measured.counts.storageCalls)
        }
        print("PASS migrated SSI final point/empty callback cancellation")
    }

    public static func verifyApplicability() throws {
        var nonclamped = NativeExactFixtures.plane()
        nonclamped.uKnots = [-2, -1, 1, 2]; nonclamped.vKnots = [-2, -1, 1, 2]
        for reverse in [false, true] {
            let result = try rich(.ordinary, reverse ? L6SurfaceSurfaceFixtures.tangency() : nonclamped,
                reverse ? nonclamped : L6SurfaceSurfaceFixtures.tangency())
            try NativeExactFixtures.require(try !authority(result).geometry.isEmpty && result.intersections.count == 1)
        }
        let multi = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 0.5, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.init(x: 0, y: 0, z: 0), .init(x: 0.5, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 0, y: 1, z: 0), .init(x: 0.5, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        var periodic = NativeExactFixtures.plane()
        periodic.isUPeriodic = true; periodic.uKnots = [0, 1, 2, 3]
        for row in periodic.controlPoints.indices {
            periodic.controlPoints[row][1] = periodic.controlPoints[row][0]
        }
        try periodic.validate(tolerance: .standard)
        for source in [multi, periodic] {
            let allowance = Allowance(work: 0, bytes: 0)
            let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: 64, maximumSubdivisionDepth: 0,
                remainingSourceDepth: 1, consumeWork: { try allowance.work() },
                consumeStorage: { try allowance.storage($0) }, maximumAlgebraicDepth: 32)
            let declined = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: .bSpline(source),
                second: .bSpline(NativeExactFixtures.plane()), options: .init(), tolerance: .standard,
                includeRelations: true, admission: admission)
            try NativeExactFixtures.require(declined == nil && allowance.counts.work == 0 && allowance.counts.bytes == 0)
        }
        let fallback = Allowance()
        let solver: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        let original = try solver.intersectionResult(first: .bSpline(multi),
            second: .bSpline(L6SurfaceSurfaceFixtures.perpendicular()), options: .init(), tolerance: .standard,
            maximumSpanCount: 64, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { try fallback.work() }, consumeStorage: { try fallback.storage($0) },
            maximumAlgebraicDepth: 32)
        guard let old = original.originalNativeRelations else { throw NativeExactFixtures.Failure.invalidEvidence }
        try NativeExactFixtures.require(original.originalExactGeometricRelation == nil
            && old.sourceChartCount == 2 && old.componentCount == 1 && old.hasPositiveDimensionalParameters)
        let refused = Allowance(work: 0)
        do {
            _ = try solver.intersectionResult(first: .bSpline(periodic), second: .bSpline(NativeExactFixtures.plane()),
                options: .init(), tolerance: .standard, maximumSpanCount: 64, maximumSubdivisionDepth: 0,
                remainingSourceDepth: 1, consumeWork: { try refused.work() },
                consumeStorage: { try refused.storage($0) }, maximumAlgebraicDepth: 32)
            throw NativeExactFixtures.Failure.invalidEvidence
        } catch Rejection.work { }
        for invalid in [false, true] {
            var malformed = NativeExactFixtures.plane()
            malformed.uKnots = invalid ? [0, 0, 0, 0] : [0, 0, 1]
            let allowance = Allowance()
            let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: 1, maximumSubdivisionDepth: 0,
                remainingSourceDepth: 1, consumeWork: { try allowance.work() },
                consumeStorage: { try allowance.storage($0) }, maximumAlgebraicDepth: 32)
            do {
                _ = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: .bSpline(malformed),
                    second: .bSpline(NativeExactFixtures.plane()), options: .init(), tolerance: .standard,
                    includeRelations: true, admission: admission)
                throw NativeExactFixtures.Failure.invalidEvidence
            } catch GeometryError.invalidDistance(let value) {
                try NativeExactFixtures.require(value == (invalid ? 0 : 3))
            }
            try NativeExactFixtures.require(allowance.counts.work > 0)
        }
        print("PASS migrated SSI nonclamped source, pure family decline and unchanged multi-chart/periodic fallback")
    }
}
