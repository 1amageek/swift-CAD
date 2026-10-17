import CADCore
@testable import CADGeometry
import Synchronization

enum LinearPlaneWholeSupportChecks {
    struct Failure: Error { let message: String }
    final class CheckpointObserver: Sendable {
        let counter = Mutex(0)
        func advance() -> Int { counter.withLock { $0 += 1; return $0 } }
        var count: Int { counter.withLock { $0 } }
    }
    static let tolerance = ModelingTolerance.standard
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }
    static func limits(value: Int = 32, coefficient: Int = 32, source: Int = 1, geometric: Int = 8) throws -> OriginalQueryExecutionLimits {
        try .init(maximumValueDepth: value, maximumCoefficientDepth: coefficient,
            remainingSourceDepth: source, maximumSubdivisionDepth: geometric, maximumSpans: 262_144)
    }
    static func execution(_ budget: OriginalQueryBudget, value: Int = 32, coefficient: Int = 32,
        source: Int = 1, geometric: Int = 8) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try limits(value: value, coefficient: coefficient, source: source, geometric: geometric))
    }
    static func budget() throws -> OriginalQueryBudget {
        try .init(workLimit: 8_388_608, storageByteLimit: 268_435_456)
    }
    static func line(_ origin: Point3D = .origin, _ direction: Vector3D = .unitZ) -> Curve3D {
        .line(.init(origin: origin, direction: direction))
    }
    static func plane(_ origin: Point3D = .init(x: 0, y: 0, z: 0.005), _ normal: Vector3D = .unitZ) -> Surface3D {
        .plane(.init(origin: origin, normal: normal))
    }
    static func options(_ lower: Double = 0, _ upper: Double = 0.01,
        u: ScalarInterval? = nil, v: ScalarInterval? = nil) throws -> CurveSurfaceIntersectionOptions {
        .init(curveRange: try .init(lower: lower, upper: upper), surfaceURange: u, surfaceVRange: v)
    }
    static func issue(_ curve: Curve3D = line(), _ surface: Surface3D = plane(),
        _ options: CurveSurfaceIntersectionOptions? = nil, using a: inout OriginalQueryExecution) throws -> CurveSurfaceIntersectionResult {
        let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        return try resolver.intersectionResult(curve: curve, surface: surface,
            options: options ?? Self.options(), tolerance: tolerance, using: &a)
    }
    typealias Q = ExactRationalCoefficient
    struct RationalVector: Sendable {
        let x: Q
        let y: Q
        let z: Q
        init(x: Q, y: Q, z: Q) { self.x = x; self.y = y; self.z = z }
        init(_ point: Point3D, using a: inout OriginalQueryExecution) throws {
            x = try .originalDouble(point.x, usage: &a)
            y = try .originalDouble(point.y, usage: &a)
            z = try .originalDouble(point.z, usage: &a)
        }
        init(_ vector: Vector3D, using a: inout OriginalQueryExecution) throws {
            x = try .originalDouble(vector.x, usage: &a)
            y = try .originalDouble(vector.y, usage: &a)
            z = try .originalDouble(vector.z, usage: &a)
        }
        func dot(_ other: Self, using a: inout OriginalQueryExecution) throws -> Q {
            let first = try x.multiplied(by: other.x, usage: &a)
            let second = try y.multiplied(by: other.y, usage: &a)
            let third = try z.multiplied(by: other.z, usage: &a)
            return try first.adding(second, usage: &a).adding(third, usage: &a)
        }
        func cross(_ other: Self, using a: inout OriginalQueryExecution) throws -> Self {
            try .init(x: y.multiplied(by: other.z, usage: &a).subtracting(z.multiplied(by: other.y, usage: &a), usage: &a),
                y: z.multiplied(by: other.x, usage: &a).subtracting(x.multiplied(by: other.z, usage: &a), usage: &a),
                z: x.multiplied(by: other.y, usage: &a).subtracting(y.multiplied(by: other.x, usage: &a), usage: &a))
        }
        func subtracting(_ other: Self, using a: inout OriginalQueryExecution) throws -> Self {
            try .init(x: x.subtracting(other.x, usage: &a), y: y.subtracting(other.y, usage: &a),
                z: z.subtracting(other.z, usage: &a))
        }
        func point(at t: Q, direction: Self, using a: inout OriginalQueryExecution) throws -> Self {
            try .init(x: x.adding(direction.x.multiplied(by: t, usage: &a), usage: &a),
                y: y.adding(direction.y.multiplied(by: t, usage: &a), usage: &a),
                z: z.adding(direction.z.multiplied(by: t, usage: &a), usage: &a))
        }
    }
    struct CoordinateExpectation: Sendable {
        let square: Q
        let sign: ExactOrder
        init(square: Q, numerator: Q) {
            self.square = square
            sign = numerator.isNegative ? .less : numerator.isPositive ? .greater : .equal
        }
        init(rational: Q, using a: inout OriginalQueryExecution) throws {
            self.init(square: try rational.multiplied(by: rational, usage: &a), numerator: rational)
        }
    }
    static func coordinateExpectations(curve: Curve3D, surface: Surface3D, t: Q,
        using a: inout OriginalQueryExecution) throws -> [CoordinateExpectation] {
        guard case .line(let line) = curve, case .plane(let plane) = surface, plane.uDirection == nil else {
            throw Failure(message: "The independent authored plane oracle requires its actual stored-N inputs.")
        }
        let origin = try RationalVector(line.origin, using: &a)
        let direction = try RationalVector(line.direction, using: &a)
        let planeOrigin = try RationalVector(plane.origin, using: &a)
        let normal = try RationalVector(plane.normal, using: &a)
        // The source rule selects X on a tie, then uses C=N cross R.
        let nx = normal.x.isNegative ? normal.x.negated : normal.x
        let ny = normal.y.isNegative ? normal.y.negated : normal.y
        let reference = try nx.subtracting(ny, usage: &a).isPositive
            ? RationalVector(x: .zero, y: .one, z: .zero)
            : RationalVector(x: .one, y: .zero, z: .zero)
        let cross = try normal.cross(reference, using: &a)
        let secondCross = try normal.cross(cross, using: &a)
        let firstSquare = try cross.dot(cross, using: &a)
        let normalSquare = try normal.dot(normal, using: &a)
        try require(firstSquare.isPositive && normalSquare.isPositive,
            "The independent source basis has a nonpositive squared length.")
        let point = try origin.point(at: t, direction: direction, using: &a)
        let delta = try point.subtracting(planeOrigin, using: &a)
        try require(delta.dot(normal, using: &a).isZero,
            "The independent authored point does not lie on the requested plane.")
        let uNumerator = try delta.dot(cross, using: &a)
        let vNumerator = try delta.dot(secondCross, using: &a)
        let uSquare = try uNumerator.multiplied(by: uNumerator, usage: &a).divided(by: firstSquare, usage: &a)
        let vSquare = try vNumerator.multiplied(by: vNumerator, usage: &a)
            .divided(by: firstSquare.multiplied(by: normalSquare, usage: &a), usage: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: CoordinateExpectation.self))
        return [try .init(rational: t, using: &a), .init(square: uSquare, numerator: uNumerator),
            .init(square: vSquare, numerator: vNumerator), try .init(rational: point.x, using: &a),
            try .init(rational: point.y, using: &a), try .init(rational: point.z, using: &a)]
    }
    static func magnitudeWithin(_ expected: CoordinateExpectation, proposal: Double, epsilon: Q,
        using a: inout OriginalQueryExecution) throws -> Bool {
        let raw = try Q.originalDouble(proposal, usage: &a)
        // Exact zero also uses +proposal, so a false nonzero proposal is rejected.
        let oriented = expected.sign == .less ? raw.negated : raw
        let lower = try oriented.subtracting(epsilon, usage: &a)
        let upper = try oriented.adding(epsilon, usage: &a)
        if upper.isNegative { return false }
        if lower.isPositive,
            try lower.multiplied(by: lower, usage: &a).subtracting(expected.square, usage: &a).isPositive { return false }
        return try !expected.square.subtracting(upper.multiplied(by: upper, usage: &a), usage: &a).isPositive
    }
    static func exact(_ result: CurveSurfaceIntersectionResult, curve: Curve3D = line(), surface: Surface3D = plane(),
        tNumerator: Int = 0, tDenominator: Int = 1, authoredT: Double? = nil, using a: inout OriginalQueryExecution) throws {
        guard let geometry = result.originalIssuedGeometricRelation, let point = geometry.exactPoints.first else {
            throw Failure(message: "The public result lost its original exact T/UV/image owner.")
        }
        try require(!geometry.isEmpty && !geometry.hasPositiveDimensionalSolutions && !geometry.pairs.isEmpty,
            "The isolated original product has invalid complete coverage.")
        try require(point.firstParameters.count == 1 && point.secondParameters.count == 2,
            "The result discarded original T or either plane UV coordinate.")
        let f = point.local.witness.field
        let expected: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>.Value
        if let authoredT { expected = try f.binary64(exactly: authoredT, using: &a) }
        else { expected = try f.dividing(f.integer(tNumerator, using: &a), f.integer(tDenominator, using: &a), using: &a) }
        try require(f.compare(point.firstParameters[0], expected, using: &a) == .equal,
            "The exact authored T differs from the independent linear equation.")
        try require(point.pairOrdinal >= 0 && point.pairOrdinal < geometry.pairs.count,
            "The original point lost its actual solved pair ordinal.")
        let solved = geometry.pairs[point.pairOrdinal].original
        try require(solved.firstGraphIndex == 0 && solved.secondGraphIndex == 0,
            "Selected solving changed the original chart ordinals.")
        let selected = solved.relation.original.first.predicate.source.domains[0]
        guard selected.includesLower, selected.includesUpper,
            case .finite(let lower) = selected.lower, case .finite(let upper) = selected.upper else {
            throw Failure(message: "The actual solved graph lost its proved closed singleton T domain.")
        }
        try require(f.compare(f.importing(lower, using: &a), expected, using: &a) == .equal &&
            f.compare(f.importing(upper, using: &a), expected, using: &a) == .equal,
            "Public transport was attached to a graph other than the solved source singleton.")
        let planeDomains = solved.relation.original.second.predicate.source.domains
        try require(planeDomains.count == 2, "The solved plane lost an authored UV parameter slot.")
        for axis in 0..<2 {
            let domain = planeDomains[axis]
            guard domain.includesLower, domain.includesUpper,
                case .finite(let lower) = domain.lower, case .finite(let upper) = domain.upper else {
                throw Failure(message: "The actual solved plane lost its source-proved singleton UV domain.")
            }
            try require(f.compare(f.importing(lower, using: &a), point.secondParameters[axis], using: &a) == .equal &&
                f.compare(f.importing(upper, using: &a), point.secondParameters[axis], using: &a) == .equal,
                "Public UV was attached to a plane graph other than the actual solved original tuple.")
        }
        guard let numeric = result.points.first, result.points.count == 1 else {
            throw Failure(message: "The proved isolated tuple lost its numerical representative.")
        }
        let proposals = [numeric.curveParameter, numeric.surfaceU, numeric.surfaceV,
            numeric.point.x, numeric.point.y, numeric.point.z]
        let originals = [point.firstParameters[0], point.secondParameters[0], point.secondParameters[1],
            point.position.x, point.position.y, point.position.z]
        let rationalT: Q
        if let authoredT { rationalT = try .originalDouble(authoredT, usage: &a) }
        else { rationalT = try Q.originalInteger(tNumerator, usage: &a).divided(by: .originalInteger(tDenominator, usage: &a), usage: &a) }
        let expectations = try coordinateExpectations(curve: curve, surface: surface, t: rationalT, using: &a)
        let epsilon = try Q.originalDouble(tolerance.distance, usage: &a)
        let zero = try f.integer(0, using: &a)
        for axis in 0..<6 {
            let expected = expectations[axis]
            let expectedSquare = try f.importingBase(f.context.base.rational(exactly: expected.square, using: &a), using: &a)
            let actualSquare = try f.multiplying(originals[axis], originals[axis], using: &a)
            try require(f.compare(actualSquare, expectedSquare, using: &a) == .equal,
                "The original coordinate square differs from the independent authored equation.")
            try require(f.compare(originals[axis], zero, using: &a) == expected.sign,
                "The original coordinate sign differs from the independent authored equation.")
            try require(magnitudeWithin(expected, proposal: proposals[axis], epsilon: epsilon, using: &a),
                "The numerical coordinate escaped the exact retained tuple's declared accuracy.")
        }
        for pair in geometry.pairs {
            for stratum in pair.geometry.strata {
                try require(stratum.parameterDimension == 0 && stratum.imageDimension == 0 && stratum.fiberDimension == 0,
                    "The isolated original T/UV image/fibre dimension changed.")
            }
        }
    }
    static func finiteAndOrdinaryParity() throws {
        let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        let ordinary = try resolver.intersectionResult(curve: line(), surface: plane(), options: options(), tolerance: tolerance)
        var a = try execution(budget())
        let admitted = try issue(using: &a)
        try exact(ordinary, authoredT: 0.005, using: &a)
        try exact(admitted, authoredT: 0.005, using: &a)
        let epsilon = try Q.originalDouble(tolerance.distance, usage: &a)
        let falseProposal = CoordinateExpectation(square: .one, numerator: .one)
        try require(!magnitudeWithin(falseProposal, proposal: 0, epsilon: epsilon, using: &a),
            "The numerical accuracy oracle admitted a displaced proposal.")
        try require(ordinary.points == admitted.points && admitted.points.count == 1,
            "Ordinary and direct contexts selected different original line/plane laws.")
        let bare: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector()
        let points = try bare.intersections(curve: line(), surface: plane(), options: options(), tolerance: tolerance, using: &a)
        try require(points == admitted.points, "Bare and rich isolated publication disagree.")
    }
    static func endpointEmptyAndParallel() throws {
        var a = try execution(budget())
        let lower = try issue(line(), plane(), options(0.005, 0.01), using: &a)
        try exact(lower, authoredT: 0.005, using: &a)
        let upper = try issue(line(), plane(), options(0, 0.005), using: &a)
        try exact(upper, authoredT: 0.005, using: &a)
        for request in [try options(0.006, 0.01), try options(-0.01, 0)] {
            let empty = try issue(line(), plane(), request, using: &a)
            try require(empty.originalIssuedGeometricRelation?.isEmpty == true && empty.points.isEmpty,
                "Whole selected-domain exclusion was not retained as complete empty.")
        }
        let parallel = try issue(line(.origin, .unitX), plane(), options(0, 1), using: &a)
        try require(parallel.originalIssuedGeometricRelation?.isEmpty == true, "Parallel disjoint supports did not exclude the whole product.")
    }
    static func containedAndRequestedUV() throws {
        var a = try execution(budget())
        let curve = line(.origin, .unitX), support = plane(.origin)
        let contained = try issue(curve, support, options(0, 1), using: &a)
        try require(contained.hasPositiveDimensionalSolutions && contained.representation == .exactRelation,
            "Contained line was reduced to empty or endpoint-only numerical success.")
        guard let fullPair = contained.originalIssuedGeometricRelation?.pairs.first else {
            throw Failure(message: "Contained whole-T relation lost its solved graph.")
        }
        let wholeSource = fullPair.original.relation.original.first.predicate.source
        let cells = try ExactRealCellDomain<OriginalExactScalarDomain>(retaining: wholeSource, using: &a)
        let wholeField = try cells.coefficientField(of: wholeSource, using: &a)
        let fullDomain = wholeSource.domains[0]
        guard case .finite(let lower) = fullDomain.lower, case .finite(let upper) = fullDomain.upper else {
            throw Failure(message: "Contained T support changed its finite original endpoints.")
        }
        try require(wholeField.compare(lower, wholeField.integer(0, using: &a), using: &a) == .equal &&
            wholeField.compare(upper, wholeField.integer(1, using: &a), using: &a) == .equal,
            "An identically zero incidence law restricted the original whole-T request.")
        for domain in fullPair.original.relation.original.second.predicate.source.domains {
            guard case .negativeInfinity = domain.lower, case .positiveInfinity = domain.upper else {
                throw Failure(message: "Contained incidence replaced the original whole-plane UV support.")
            }
        }
        guard let geometry = contained.originalIssuedGeometricRelation else { throw Failure(message: "Contained original owner missing.") }
        try require(geometry.pairs.contains { $0.geometry.strata.contains { $0.parameterDimension == 1 && $0.imageDimension == 1 && $0.fiberDimension == 0 } },
            "Contained original interval lost its image/fibre evidence.")
        let bare: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector()
        do {
            _ = try bare.intersections(curve: curve, surface: support, options: options(0, 1), tolerance: tolerance, using: &a)
            throw Failure(message: "Bare CS accepted a positive-dimensional original product.")
        } catch {
            guard OriginalQueryFailure.classification(of: error)?.code == .nonDiscreteIntersection else { throw error }
        }
        let shifted = line(.init(x: 1, y: 2, z: -1))
        let inside = try issue(shifted, support, options(0, 2,
            u: .init(lower: 1.5, upper: 2.5), v: .init(lower: -1.5, upper: -0.5)), using: &a)
        try exact(inside, curve: shifted, surface: support, tNumerator: 1, using: &a)
        let outside = try issue(shifted, support, options(0, 2, u: .init(lower: 3, upper: 4)), using: &a)
        try require(outside.originalIssuedGeometricRelation?.isEmpty == true,
            "Explicit original U membership was ignored or replaced by a finite search window.")
    }
    static func nonsquareNormalAndScale() throws {
        var a = try execution(budget())
        let curve = line(.init(x: 1, y: 0, z: -1))
        let result = try issue(curve, plane(.origin, .init(x: 1, y: 2, z: 3)), options(0, 1), using: &a)
        try exact(result, curve: curve, surface: plane(.origin, .init(x: 1, y: 2, z: 3)), tNumerator: 2, tDenominator: 3, using: &a)
        guard let point = result.originalIssuedGeometricRelation?.exactPoints.first else { throw Failure(message: "Nonsquare original tuple missing.") }
        let f = point.local.witness.field, u = point.secondParameters[0], v = point.secondParameters[1]
        try require(f.compare(f.multiplying(f.integer(117, using: &a), f.multiplying(u, u, using: &a), using: &a), f.integer(4, using: &a), using: &a) == .equal,
            "The original sqrt13 basis coordinate was approximated.")
        try require(f.compare(f.multiplying(f.integer(13, using: &a), f.multiplying(v, v, using: &a), using: &a), f.integer(14, using: &a), using: &a) == .equal,
            "The original sqrt14 coefficient extension was lost.")
        for scale in [0x1p400, 0x1p-400, -1.0] {
            let scaled = try issue(line(), plane(.init(x: 0, y: 0, z: 0.005), .init(x: 0, y: 0, z: scale)), using: &a)
            try exact(scaled, surface: plane(.init(x: 0, y: 0, z: 0.005), .init(x: 0, y: 0, z: scale)), authoredT: 0.005, using: &a)
        }
        // Each is an independent public request with the same unchanged caller caps.
        // The source basis issuer must validate the restored raw square laws.
        for normal in [Vector3D(x: 1, y: 2, z: 2), Vector3D(x: 1, y: 2, z: 0),
            Vector3D(x: 0, y: 1, z: 1), Vector3D(x: 40, y: 49, z: 7)] {
            var independent = try execution(budget())
            let alongZ = normal.z != 0
            let selectedLine = alongZ ? line(.init(x: 0, y: 0, z: -1)) : line(.init(x: -1, y: 0, z: 0), .unitX)
            let contact = try issue(selectedLine, plane(.origin, normal), options(0, 2), using: &independent)
            try exact(contact, curve: selectedLine, surface: plane(.origin, normal), tNumerator: 1, using: &independent)
        }
        for scale in [0x1p400, 0x1p-400, -1.0, Double.leastNonzeroMagnitude] {
            var independent = try execution(budget())
            let support = plane(.origin, .init(x: scale, y: 2 * scale, z: 3 * scale))
            let contact = try issue(curve, support, options(0, 1), using: &independent)
            try exact(contact, curve: curve, surface: support, tNumerator: 2, tDenominator: 3, using: &independent)
        }
        do {
            _ = try issue(line(), plane(.origin, .zero), using: &a)
            throw Failure(message: "A zero original normal issued a plane theorem.")
        } catch {
            guard OriginalQueryFailure.classification(of: error)?.code == .invalidInput else { throw error }
        }
    }
    static func storageRefusal(_ error: any Error) -> OriginalQueryFailure? {
        if let failure = error as? OriginalQueryFailure { return failure }
        if let failure = error as? ExactScalarFailure, case .admissionRejected(let original) = failure {
            return storageRefusal(original)
        }
        return nil
    }
    static func retainedOwnerStorageBoundary(_ result: CurveSurfaceIntersectionResult,
        depth: OriginalQueryPreparationDepth) throws {
        guard let retained = result.originalIssuedGeometricRelation as? OriginalLinearPlaneGeometricRelations else {
            throw Failure(message: "The public result lost its actual retained line/plane owner.")
        }
        let payload = MemoryLayout<OriginalLinearPlaneRelations>.stride
            + MemoryLayout<[OriginalIssuedGeometricRelationPair]>.stride
            + MemoryLayout<[OriginalIssuedExactIntersectionPoint]>.stride
            + MemoryLayout<OriginalGeometryPreparationReceipt>.stride
            + 2 * MemoryLayout<UnsafeRawPointer>.stride
        let measured = try budget(); var a = try execution(measured)
        _ = try OriginalLinearPlaneGeometricRelations.prepare(original: retained.original, pairs: retained.pairs,
            exactPoints: retained.exactPoints, depth: depth, tolerance: tolerance, using: &a)
        let cost = measured.snapshot.storageBytes
        try require(cost >= payload, "The retained owner omitted its typed payload and class header.")
        let sufficient = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: cost)
        var b = try execution(sufficient)
        let copied = try OriginalLinearPlaneGeometricRelations.prepare(original: retained.original, pairs: retained.pairs,
            exactPoints: retained.exactPoints, depth: depth, tolerance: tolerance, using: &b)
        try require(copied.pairs.count == retained.pairs.count && copied.exactPoints.count == retained.exactPoints.count,
            "Exact owner storage admission changed the retained result.")
        for ceiling in [payload - 1, cost - 1] {
            let insufficient = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: ceiling)
            var c = try execution(insufficient)
            do {
                _ = try OriginalLinearPlaneGeometricRelations.prepare(original: retained.original, pairs: retained.pairs,
                    exactPoints: retained.exactPoints, depth: depth, tolerance: tolerance, using: &c)
                throw Failure(message: "The retained owner escaped its preallocation storage boundary.")
            } catch {
                guard let failure = storageRefusal(error), failure.kernelFailure.code == .resourceLimitExceeded,
                    failure.context.resource?.axis == .storageBytes else { throw error }
            }
            if ceiling == payload - 1 {
                try require(insufficient.snapshot.work == 0 && insufficient.snapshot.storageBytes == 0,
                    "Owner construction reached preparation before its class payload was admitted.")
            }
        }
    }
    static func selectionInputStorageBoundaries() throws {
        var reader = try execution(budget())
        let field = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &reader)
        let lower = try field.integer(1, using: &reader), upper = try field.integer(2, using: &reader)
        let interval = try ExactParameterInterval.checked(field: field, lower: .finite(lower), upper: .finite(upper),
            includesLower: false, includesUpper: true, depth: .init(value: 0, coefficient: 0), using: &reader)
        let outer = try exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<OriginalExactScalar>].self)
        let inner = try exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self)
        try require(outer == MemoryLayout<[ExactParameterInterval<OriginalExactScalar>]>.stride &&
            inner == MemoryLayout<ExactParameterInterval<OriginalExactScalar>>.stride,
            "The input storage oracle changed the existing typed-payload policy.")
        for singleton in [false, true] {
            let n = outer + (singleton ? inner : 0)
            let sufficient = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: n)
            var a = try execution(sufficient)
            let input = try OriginalAffinePlaneParameterRestriction.selectionIntervals(singleton ? interval : nil, using: &a)
            try require(sufficient.snapshot.storageBytes == n && input.count == 1 && input[0].count == (singleton ? 1 : 0),
                "The selection input omitted its independent typed payload or changed its shape.")
            if singleton {
                let retained = input[0][0]
                guard case .finite(let retainedLower) = retained.lower, case .finite(let retainedUpper) = retained.upper else {
                    throw Failure(message: "The singleton input discarded its original interval endpoints.")
                }
                try require(field.compare(retainedLower, lower, using: &reader) == .equal &&
                    field.compare(retainedUpper, upper, using: &reader) == .equal &&
                    retained.includesLower == interval.includesLower && retained.includesUpper == interval.includesUpper &&
                    retained.isEmpty == interval.isEmpty && retained.depth == interval.depth,
                    "The selection input changed its retained interval owner, values or guards.")
            }
            for ceiling in [0, n - 1] {
                let insufficient = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: ceiling)
                var b = try execution(insufficient)
                do {
                    _ = try OriginalAffinePlaneParameterRestriction.selectionIntervals(singleton ? interval : nil, using: &b)
                    throw Failure(message: "The real selection input escaped independent typed N-1 or zero storage.")
                } catch {
                    guard let failure = storageRefusal(error), failure.kernelFailure.code == .resourceLimitExceeded,
                        failure.context.resource?.axis == .storageBytes else { throw error }
                }
                let expected = singleton && ceiling >= outer ? outer : 0
                try require(insufficient.snapshot.storageBytes == expected,
                    "Selection input allocation did not stop before its first unaffordable payload.")
            }
        }
    }
    static func restrictionStorageBoundaries() throws {
        let cases: [(Curve3D, Surface3D, Int)] = [
            (line(), plane(), 1),
            (line(), plane(.init(x: 0, y: 0, z: 1)), 0),
            (line(.origin, .unitX), plane(), 0)
        ]
        for (curve, surface, count) in cases {
            let measured = try budget(); var a = try execution(measured)
            let result = try issue(curve, surface, using: &a)
            try require(result.points.count == count && result.originalIssuedGeometricRelation?.hasPositiveDimensionalSolutions == false,
                "The storage control changed singleton or complete exclusion semantics.")
            let n = measured.snapshot.storageBytes
            let sufficient = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: n)
            var b = try execution(sufficient)
            let admitted = try issue(curve, surface, using: &b)
            try require(admitted.points.count == count, "Exact restriction storage changed the complete result.")
            let insufficient = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: n - 1)
            var c = try execution(insufficient)
            do {
                _ = try issue(curve, surface, using: &c)
                throw Failure(message: "Restriction scratch/output escaped exact N-1 storage admission.")
            } catch {
                guard let failure = storageRefusal(error), failure.kernelFailure.code == .resourceLimitExceeded,
                    failure.context.resource?.axis == .storageBytes else { throw error }
            }
            try require(insufficient.snapshot.storageBytes <= n - 1,
                "Rejected restriction scratch mutated storage beyond its original caller limit.")
        }
    }
    static func exactWorkAndStorageBoundaries() throws {
        let owner = try budget(); var a = try execution(owner)
        let result = try issue(using: &a)
        let cost = owner.snapshot
        let depth = try OriginalQueryPreparationDepth(scalar: .init(value: a.valueDepth, coefficient: a.coefficientDepth),
            sourceDepth: a.sourceDepth, geometricDepth: a.geometricDepth, transportDepth: a.transportDepth)
        try retainedOwnerStorageBoundary(result, depth: depth)
        try selectionInputStorageBoundaries()
        try restrictionStorageBoundaries()
        try require(cost.work > 0 && cost.storageBytes > 0, "The real source/solver/publication did no admitted work or storage.")
        for storage in [false, true] {
            let n = storage ? cost.storageBytes : cost.work
            let sufficient = try OriginalQueryBudget(workLimit: storage ? 8_388_608 : n,
                storageByteLimit: storage ? n : 268_435_456)
            var b = try execution(sufficient); _ = try issue(using: &b)
            let insufficient = try OriginalQueryBudget(workLimit: storage ? 8_388_608 : n - 1,
                storageByteLimit: storage ? n - 1 : 268_435_456)
            var c = try execution(insufficient)
            do { _ = try issue(using: &c); throw Failure(message: "Exact N-1 admission published a complete result.") }
            catch {
                guard let failure = error as? OriginalQueryFailure,
                    failure.kernelFailure.code == .resourceLimitExceeded,
                    failure.context.resource?.axis == (storage ? .storageBytes : .work) else { throw error }
            }
            try require(insufficient.snapshot.work <= insufficient.workLimit ?? Int.max,
                "Rejected work mutated its caller beyond the selected limit.")
            try require(insufficient.snapshot.storageBytes <= insufficient.storageByteLimit ?? Int.max,
                "Rejected storage mutated its caller beyond the selected limit.")
        }
    }
    static func selectedScopeAndIndependentAxes() throws {
        let owner = try budget(); var a = try execution(owner, source: 0, geometric: 0)
        let handle = try a.makeContributionHandle(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        let result = try a.withContributionScope(handle) { a in
            let start = owner.snapshot
            let result = try issue(using: &a)
            try require(handle.snapshot.work == owner.snapshot.work - start.work && handle.snapshot.storageBytes == owner.snapshot.storageBytes - start.storageBytes,
                "Source, graph or numerical publication escaped the selected caller contribution.")
            return result
        }
        try require(a.sourceDepth == 0 && a.geometricDepth == 0 && result.points.count == 1,
            "Primitive source/analytic work was assigned an unrelated geometric or source depth.")
        let measured = try budget(); var scalar = try execution(measured, source: 0, geometric: 0)
        let nonrational = line(.init(x: 1, y: 0, z: -1))
        let support = plane(.origin, .init(x: 1, y: 2, z: 3))
        _ = try issue(nonrational, support, options(0, 1), using: &scalar)
        for coefficient in [false, true] {
            let n = coefficient ? scalar.coefficientDepth : scalar.valueDepth
            var exactLimit = try execution(budget(), value: coefficient ? 32 : n,
                coefficient: coefficient ? n : 32, source: 0, geometric: 0)
            _ = try issue(nonrational, support, options(0, 1), using: &exactLimit)
            if n > 0 {
                var lower = try execution(budget(), value: coefficient ? 32 : n - 1,
                    coefficient: coefficient ? n - 1 : 32, source: 0, geometric: 0)
                do {
                    _ = try issue(nonrational, support, options(0, 1), using: &lower)
                    throw Failure(message: "Attained scalar N-1 depth published the original relation.")
                } catch {
                    guard let failure = error as? OriginalQueryFailure,
                        failure.kernelFailure.code == .resourceLimitExceeded,
                        failure.context.resource?.axis == (coefficient ? .coefficientDepth : .valueDepth) else { throw error }
                }
            }
        }
        let zero = try a.makeContributionHandle(workLimit: 0)
        let before = owner.snapshot
        do {
            _ = try a.withContributionScope(zero) { a in try issue(using: &a) }
            throw Failure(message: "Zero selected contribution admitted source work.")
        } catch {
            guard OriginalQueryFailure.classification(of: error)?.code == .resourceLimitExceeded else { throw error }
        }
        try require(zero.snapshot.work == 0 && owner.snapshot.work == before.work,
            "Selected zero-work rejection occurred after committing work.")
    }
    static func cancellationAtEntryInteriorAndPublication() throws {
        let baseline = CheckpointObserver()
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
            checkpoint: { _ = baseline.advance() })
        var a = try execution(budget); _ = try issue(using: &a)
        let total = baseline.count
        try require(total > 3, "The actual source/solver path has no interior cancellation checkpoint.")
        for stop in [1, total / 2, total] {
            let counter = CheckpointObserver()
            let interrupted = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456, checkpoint: {
                let cancelled = counter.advance() == stop
                if cancelled { throw CancellationError() }
            })
            var b = try execution(interrupted)
            do { _ = try issue(using: &b); throw Failure(message: "Cancellation published a complete original result.") }
            catch is CancellationError {}
            try require(counter.count == stop, "Cancellation did not stop at the observed exact checkpoint.")
        }
    }
    static func originalScalarFailure(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return originalScalarFailure(failure.originalError) }
        if let failure = error as? ExactScalarFailure, case .admissionRejected(let original) = failure {
            return originalScalarFailure(original)
        }
        return error
    }
    static func retainedCoefficientRootReaders() throws {
        func fieldsAfterSourceRelease() throws -> (OriginalExactScalarDomain, OriginalExactScalarDomain, Int) {
            var a = try execution(budget(), source: 0, geometric: 0)
            let sealed = try a.withProofScope(valueAxis: .coefficient) { a in
                let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &a)
                let equation = try x.multiplied(by: x, usage: &a)
                    .subtracting(.constant(.originalDouble(2, usage: &a), usage: &a), usage: &a)
                let roots = try ExactUnivariateRootIsolator().isolate(equation,
                    lower: .one, upper: .originalDouble(2, usage: &a), maximumDepth: 32, usage: &a)
                try require(roots.count == 1, "The positive coefficient selector is not unique.")
                return try ExactAlgebraicRealRoot(polynomial: equation, isolation: roots[0], usage: &a)
                    .refined(maximumWidth: .one.divided(by: .originalDouble(16, usage: &a), usage: &a),
                        maximumDepth: 32, usage: &a)
            }
            let direct = try OriginalExactScalarDomain(root: sealed, axis: .coefficient,
                maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
            let parent = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
            let extended = try OriginalExactScalarDomain(extending: parent, root: sealed, axis: .coefficient, using: &a)
            return (direct, extended, sealed.isolation.isolationDepth)
        }
        let (direct, extended, attained) = try fieldsAfterSourceRelease()
        try require(attained > 0, "The independent depth control did not refine its root bracket.")
        for field in [direct, extended] {
            let paid = try budget(); var reader = try execution(paid, coefficient: attained, source: 0, geometric: 0)
            let value = try field.generator(using: &reader)
            let one = try field.integer(1, using: &reader), two = try field.integer(2, using: &reader)
            for _ in 0..<2 {
                let before = paid.snapshot.work
                try require(field.compare(value, one, using: &reader) == .greater,
                    "Retaining the coefficient root changed its positive selector.")
                try require(field.compare(field.multiplying(value, value, using: &reader), two, using: &reader) == .equal,
                    "Retaining the coefficient root changed its original square law.")
                try require(paid.snapshot.work > before && reader.coefficientDepth == attained && reader.valueDepth == 0,
                    "A retained root comparison escaped its reader admission or changed the depth axis.")
            }
            var lower = try execution(budget(), coefficient: attained - 1, source: 0, geometric: 0)
            do {
                _ = try field.compare(value, one, using: &lower)
                throw Failure(message: "A retained coefficient root escaped independent N-1 depth.")
            } catch {
                guard let failure = originalScalarFailure(error) as? ExactScalarFailure,
                    case .resourceLimit(.coefficientDepth) = failure else { throw error }
            }
            let cancelled = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
                checkpoint: { throw CancellationError() })
            var interrupted = try execution(cancelled, source: 0, geometric: 0)
            do {
                _ = try field.compare(value, one, using: &interrupted)
                throw Failure(message: "A retained root comparison ignored reader cancellation.")
            } catch {
                guard let failure = originalScalarFailure(error) as? ExactScalarFailure,
                    case .cancelled = failure else { throw error }
            }
        }
    }
    static func retainedSourceLifetimeAndCOW() throws {
        try retainedCoefficientRootReaders()
        func retained() throws -> CurveSurfaceIntersectionResult {
            var curve = line(), support = plane()
            var a = try execution(budget())
            let result = try issue(curve, support, using: &a)
            curve = line(.init(x: 0, y: 0, z: 2)); support = plane(.init(x: 0, y: 0, z: 3))
            try require(curve != line() && support != plane(), "The caller source mutation control did not change.")
            return result
        }
        let result = try retained()
        var independent = try execution(budget())
        try exact(result, authoredT: 0.005, using: &independent)
        guard let point = result.originalIssuedGeometricRelation?.exactPoints.first else { throw Failure(message: "Retained source was released.") }
        let f = point.local.witness.field
        try require(f.compare(point.position.z, f.binary64(exactly: 0.005, using: &independent), using: &independent) == .equal,
            "A released/mutated caller source changed the retained exact XYZ law.")
        guard let numerical = result.originalIssuedNumericalPoints else { throw Failure(message: "Retained numerical incidence missing.") }
        try require(!point.sourceRelation.pairs.isEmpty && !numerical.incidenceRanges.isEmpty,
            "Retained full relation or exact-to-numerical incidence owner was lost.")
    }
    static let checks: [(String, @Sendable () throws -> Void)] = [
        ("finite and ordinary parity", finiteAndOrdinaryParity),
        ("endpoint empty and parallel", endpointEmptyAndParallel),
        ("contained and requested UV", containedAndRequestedUV),
        ("nonsquare normal and scale", nonsquareNormalAndScale),
        ("exact work and storage", exactWorkAndStorageBoundaries),
        ("selected scope and independent axes", selectedScopeAndIndependentAxes),
        ("entry interior publication cancellation", cancellationAtEntryInteriorAndPublication),
        ("retained source lifetime and COW", retainedSourceLifetimeAndCOW)
    ]
}
