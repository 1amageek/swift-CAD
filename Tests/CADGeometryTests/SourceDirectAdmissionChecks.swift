import CADCore
@testable import CADGeometry
import Synchronization

/// Behavioral checks shared unchanged by Native, normal WASM and Embedded clients.
enum SourceDirectAdmissionChecks {
    struct Failure: Error {
        let detail: String
        let line: Int
        init(detail: String, line: Int = #line) { self.detail = detail; self.line = line }
    }
    private static func require(_ condition: Bool, _ detail: String, line: Int = #line) throws {
        guard condition else { throw Failure(detail: detail, line: line) }
    }
    private static func requireValue<Value>(_ value: Value?, line: Int = #line) throws -> Value {
        guard let value else { throw Failure(detail: "The original source owner declined a required proof.", line: line) }
        return value
    }

    private enum StorageProbeFailure: Error { case factorPayload }

    private static func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16)
        throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: sourceDepth, maximumTransportDepth: 16,
                maximumSubdivisionDepth: 32))
    }

    private static func queryFailure(_ error: any Error) -> OriginalQueryFailure? {
        if let failure = error as? OriginalQueryFailure { return failure }
        if case .admissionRejected(let retained)? = error as? ExactScalarFailure {
            return queryFailure(retained)
        }
        return nil
    }

    private static func originalError(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return originalError(failure.originalError) }
        if case .admissionRejected(let retained)? = error as? ExactScalarFailure {
            return originalError(retained)
        }
        return error
    }

    static func stationaryNativeSupportCannotResetCallerSourceDepth() throws {
        let surface = BSplineSurface3D.bilinearPatch(
            bottomLeft: .init(x: 0, y: 0, z: 0),
            bottomRight: .init(x: 1, y: 0, z: 0),
            topRight: .init(x: 2, y: 0, z: 0),
            topLeft: .init(x: 0, y: 1, z: 0))
        let validator = BSplineSurfaceEmbeddingValidator()
        var ordinary = try Self.execution(OriginalQueryBudget())
        try validator.validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain,
            tolerance: .standard, allowStationaryBoundaryParameterization: true, using: &ordinary)
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        var limited = try Self.execution(budget, sourceDepth: 0)
        do {
            try limited.withSourceDepthOffset(1) { execution in
                try validator.validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain,
                    tolerance: .standard, allowStationaryBoundaryParameterization: true, using: &execution)
            }
            throw SourceDirectAdmissionChecks.Failure(detail: "The stationary source resolver escaped the caller-relative source ceiling.")
        } catch {
            try SourceDirectAdmissionChecks.require(Self.queryFailure(error)?.context.resource?.axis == .sourceDepth, "Original source admission oracle failed.")
        }
    }

    static func originalGainAdmitsItsActualFactorPayloadBeforeRetention() throws {
        let factorStride = MemoryLayout<OriginalParameterGain>.stride
        let budget = try OriginalQueryBudget(consumeStorageBytes: { bytes in
            if bytes == factorStride { throw StorageProbeFailure.factorPayload }
        })
        var execution = try Self.execution(budget)
        do {
            _ = try OriginalParameterGain.originalProduct(factors: [.binary(1)], usage: &execution)
            throw SourceDirectAdmissionChecks.Failure(detail: "The original factor payload was retained without its typed allocation admission.")
        } catch {
            guard case StorageProbeFailure.factorPayload = Self.originalError(error) else { throw error }
        }
    }

    private static func expectResource(_ axis: ExactResource, _ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard case .resourceLimit(let actual)? = originalError(error) as? ExactScalarFailure else { throw error }
            try SourceDirectAdmissionChecks.require(actual == axis, "Original source admission oracle failed.")
            return
        }
        throw SourceDirectAdmissionChecks.Failure(detail: "An exhausted caller published a source result.")
    }

    private static func stationary(_ execution: inout OriginalQueryExecution) throws {
        let surface = BSplineSurface3D.bilinearPatch(bottomLeft: .origin,
            bottomRight: .init(x: 1, y: 0, z: 0), topRight: .init(x: 2, y: 0, z: 0),
            topLeft: .init(x: 0, y: 1, z: 0))
        try BSplineSurfaceEmbeddingValidator().validate(surface, uDomain: surface.uDomain,
            vDomain: surface.vDomain, tolerance: .standard,
            allowStationaryBoundaryParameterization: true, using: &execution)
    }
    private static func gain(_ execution: inout OriginalQueryExecution) throws {
        let product = try OriginalParameterGain.originalProduct(
            factors: [.binary(2), .ratio(numerator: 3, denominator: 2)], usage: &execution)
        try SourceDirectAdmissionChecks.require(product.value == 3, "Original source admission oracle failed.")
    }

    static func sourceOperationsPreserveExactCallerResourceBoundaries(native: Bool) throws {
        func run(_ budget: OriginalQueryBudget) throws {
            var execution = try Self.execution(budget)
            try execution.consumeWork(7)
            try execution.retainStorage(bytes: 11)
            if native { try Self.stationary(&execution) } else { try Self.gain(&execution) }
        }
        let measured = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
        try run(measured)
        let cost = measured.snapshot
        try SourceDirectAdmissionChecks.require(cost.work > 7 && cost.storageBytes > 11, "Original source admission oracle failed.")
        let exact = try OriginalQueryBudget(workLimit: cost.work, storageByteLimit: cost.storageBytes)
        try run(exact)
        try SourceDirectAdmissionChecks.require(exact.snapshot.work == cost.work && exact.snapshot.storageBytes == cost.storageBytes, "Original source admission oracle failed.")
        for axis in [ExactResource.work, .storage] {
            let limited = try OriginalQueryBudget(workLimit: axis == .work ? cost.work - 1 : cost.work,
                storageByteLimit: axis == .storage ? cost.storageBytes - 1 : cost.storageBytes)
            try Self.expectResource(axis) { try run(limited) }
            try SourceDirectAdmissionChecks.require(limited.snapshot.work <= cost.work && limited.snapshot.storageBytes <= cost.storageBytes, "Original source admission oracle failed.")
        }
        try Self.expectResource(.work) { try run(exact) }
    }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws {
            let next = state.withLock { value in value += 1; return value }
            if next == stop { throw CancellationError() }
        }
    }

    static func sourceOperationsObserveEntryAndTerminalCancellation(native: Bool) throws {
        let observed = Checkpoints()
        let measured = try OriginalQueryBudget(checkpoint: { try observed.checkpoint() })
        var normal = try Self.execution(measured)
        if native { try Self.stationary(&normal) } else { try Self.gain(&normal) }
        try SourceDirectAdmissionChecks.require(observed.count > 1, "Original source admission oracle failed.")
        for stop in [1, observed.count] {
            let cancellation = Checkpoints(stop: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try cancellation.checkpoint() })
            var execution = try Self.execution(budget)
            do {
                if native { try Self.stationary(&execution) } else { try Self.gain(&execution) }
                throw SourceDirectAdmissionChecks.Failure(detail: "A cancelled source operation published a result.")
            } catch {
                let cause = Self.originalError(error)
                if let scalar = cause as? ExactScalarFailure {
                    guard case .cancelled = scalar else { throw error }
                }
                else { try SourceDirectAdmissionChecks.require(cause is CancellationError, "Original source admission oracle failed.") }
            }
            try SourceDirectAdmissionChecks.require(cancellation.count == stop, "Original source admission oracle failed.")
            if stop == 1 { try SourceDirectAdmissionChecks.require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0, "Original source admission oracle failed.") }
        }
    }

    static func factorOwnersAndIndependentZeroDepthKeepTheOriginalImageLaw() throws {
        var factors: [OriginalParameterGain] = [.binary(2), .binary(3)]
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 0, maximumCoefficientDepth: 0))
        let retained = try OriginalParameterGain.originalProduct(factors: factors, usage: &execution)
        factors[0] = .binary(9)
        try SourceDirectAdmissionChecks.require(retained.value == 6, "Original source admission oracle failed.")
        guard case .product(let payload) = retained else { throw SourceDirectAdmissionChecks.Failure(detail: "Lost original product payload.") }
        try SourceDirectAdmissionChecks.require(payload.factors == [.binary(2), .binary(3)], "Original source admission oracle failed.")
        let nested = try OriginalParameterGain.originalProduct(factors: [retained, .binary(-2)], usage: &execution)
        try SourceDirectAdmissionChecks.require(nested.value == -12, "Original source admission oracle failed.")
        guard case .product(let flattened) = nested else { throw SourceDirectAdmissionChecks.Failure(detail: "Lost nested original factors.") }
        try SourceDirectAdmissionChecks.require(flattened.factors == [.binary(2), .binary(3), .binary(-2)], "Original source admission oracle failed.")
        let source = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let image = try ParameterImageCurve3D(source: source, gain: -2, offset: 1, tolerance: .standard)
        let range = try ScalarInterval(lower: 0, upper: 1)
        let ordinary = try image.sourceParameterBounds(over: range, tolerance: .standard)
        var direct = try Self.execution(OriginalQueryBudget())
        let admitted = try image.sourceParameterBounds(over: range, tolerance: .standard, using: &direct)
        // The authored affine law 1 - 2t maps the closed domain onto [-1, 1].
        try SourceDirectAdmissionChecks.require(ordinary.contains(-1) && ordinary.contains(0) && ordinary.contains(1), "Original source admission oracle failed.")
        try SourceDirectAdmissionChecks.require(admitted.contains(-1) && admitted.contains(0) && admitted.contains(1), "Original source admission oracle failed.")
        try SourceDirectAdmissionChecks.require(try image.sourceParameter(at: 0.25, tolerance: .standard, using: &direct) == 0.5, "Original source admission oracle failed.")
    }


    enum Graph {

        private enum ProbeFailure: Error { case sourceProjection }

        private static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
            OriginalQueryExecution(budget: budget,
                limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                    remainingSourceDepth: 16, maximumTransportDepth: 16,
                    maximumSubdivisionDepth: 32))
        }
        private static func originalError(_ error: any Error) -> any Error {
            if let value = error as? OriginalQueryFailure { return originalError(value.originalError) }
            if case .admissionRejected(let value)? = error as? ExactScalarFailure { return originalError(value) }
            return error
        }

        static func selectedMiddleCurveJetsUseTheCallerStorageAdmission(restricted: Bool) throws {
            let source = BSplineSurface3D(uDegree: 1, vDegree: 2,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 0.5, 0.5, 1, 1, 1],
                controlPoints: [0.0, 0.25, 0.5, 0.75, 1.0].map { v in
                    [Point3D(x: 0, y: v, z: v - 0.5), Point3D(x: 1, y: v, z: v - 0.5)]
                })
            let plane = BSplineSurface3D.bilinearPatch(bottomLeft: .origin,
                bottomRight: .init(x: 1, y: 0, z: 0), topRight: .init(x: 1, y: 1, z: 0),
                topLeft: .init(x: 0, y: 1, z: 0))
            var setup = try execution(OriginalQueryBudget())
            let graph = try SourceDirectAdmissionChecks.requireValue(try ExactIsoparametricPlanarIntersectionGraph.certified(
                first: source, second: plane, tolerance: .standard, using: &setup))
            let cell = try SourceDirectAdmissionChecks.requireValue(graph.cells.first)
            let bounds = SurfaceIntersectionParameterBox(firstU: try .init(lower: 0, upper: 1),
                firstV: try .init(lower: 0, upper: 0.5), secondU: try .init(lower: 0, upper: 1),
                secondV: try .init(lower: 0, upper: 1))
            let lower = try graph.actualParameterPair(in: cell, at: 0, first: source, second: plane,
                tolerance: .standard, using: &setup)
            let middle = try graph.actualParameterPair(in: cell, at: 0.5, first: source, second: plane,
                tolerance: .standard, using: &setup)
            let upper = try graph.actualParameterPair(in: cell, at: 1, first: source, second: plane,
                tolerance: .standard, using: &setup)
            // The original curve jet owner admits eight scalar projections per control.
            let projectionBytes = 2 * 8 * MemoryLayout<OutwardScalarInterval>.stride
            let budget = try OriginalQueryBudget(consumeStorageBytes: { bytes in
                if bytes == projectionBytes { throw ProbeFailure.sourceProjection }
            })
            var query = try execution(budget)
            do {
                if restricted {
                    _ = try graph.restrictedBounds(parameterBox: bounds, freeParameter: .firstU,
                        direction: .forward, lowerAnchor: lower, midpointAnchor: middle, upperAnchor: upper,
                        fromNormalizedFraction: 0.25, toNormalizedFraction: 0.75,
                        first: source, second: plane, tolerance: .standard, using: &query)
                } else {
                    _ = try graph.parameterDerivativeBounds(parameterBox: bounds, freeParameter: .firstU,
                        direction: .forward, lowerAnchor: lower, midpointAnchor: middle, upperAnchor: upper,
                        first: source, second: plane, tolerance: .standard, using: &query)
                }
                throw SourceDirectAdmissionChecks.Failure(detail: "The selected original middle-curve jet escaped caller projection admission.")
            } catch {
                guard case ProbeFailure.sourceProjection = originalError(error) else { throw error }
            }
        }

        private static func originalQuery(restricted: Bool, direction: CertifiedImplicitIntersectionDirection = .forward,
            using query: inout OriginalQueryExecution) throws -> [ScalarInterval] {
            let source = BSplineSurface3D(uDegree: 1, vDegree: 2,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 0.5, 0.5, 1, 1, 1],
                controlPoints: [0.0, 0.25, 0.5, 0.75, 1.0].map { v in
                    [Point3D(x: 0, y: v, z: v - 0.5), Point3D(x: 1, y: v, z: v - 0.5)]
                })
            let plane = BSplineSurface3D.bilinearPatch(bottomLeft: .origin,
                bottomRight: .init(x: 1, y: 0, z: 0), topRight: .init(x: 1, y: 1, z: 0),
                topLeft: .init(x: 0, y: 1, z: 0))
            let graph = try SourceDirectAdmissionChecks.requireValue(try ExactIsoparametricPlanarIntersectionGraph.certified(
                first: source, second: plane, tolerance: .standard, using: &query))
            let cell = try SourceDirectAdmissionChecks.requireValue(graph.cells.first)
            let box = SurfaceIntersectionParameterBox(firstU: try .init(lower: 0, upper: 1),
                firstV: try .init(lower: 0, upper: 0.5), secondU: try .init(lower: 0, upper: 1),
                secondV: try .init(lower: 0, upper: 1))
            let lower = try graph.actualParameterPair(in: cell, at: 0, first: source, second: plane,
                tolerance: .standard, using: &query)
            let middle = try graph.actualParameterPair(in: cell, at: 0.5, first: source, second: plane,
                tolerance: .standard, using: &query)
            let upper = try graph.actualParameterPair(in: cell, at: 1, first: source, second: plane,
                tolerance: .standard, using: &query)
            if restricted {
                let subcell = try SourceDirectAdmissionChecks.requireValue(try graph.restrictedBounds(parameterBox: box, freeParameter: .firstU,
                    direction: direction, lowerAnchor: lower, midpointAnchor: middle, upperAnchor: upper,
                    fromNormalizedFraction: 0.25, toNormalizedFraction: 0.75,
                    first: source, second: plane, tolerance: .standard, using: &query))
                try SourceDirectAdmissionChecks.require(subcell.parameterBox.firstU.contains(0.25) && subcell.parameterBox.firstU.contains(0.75), "Original source admission oracle failed.")
                try SourceDirectAdmissionChecks.require(subcell.parameterBox.firstV.contains(0.5), "Original source admission oracle failed.")
                return subcell.parameterDerivativeBounds
            }
            return try SourceDirectAdmissionChecks.requireValue(try graph.parameterDerivativeBounds(parameterBox: box, freeParameter: .firstU,
                direction: direction, lowerAnchor: lower, midpointAnchor: middle, upperAnchor: upper,
                first: source, second: plane, tolerance: .standard, using: &query))
        }

        static func originalGraphLawsRetainDirectionsAndExactCallerLimits(restricted: Bool) throws {
            func run(_ budget: OriginalQueryBudget,
                direction: CertifiedImplicitIntersectionDirection = .forward) throws -> [ScalarInterval] {
                var query = try execution(budget)
                return try originalQuery(restricted: restricted, direction: direction, using: &query)
            }
            let measured = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456)
            let forward = try run(measured)
            let cost = measured.snapshot
            let expected = restricted ? 0.5 : 1.0
            try SourceDirectAdmissionChecks.require(forward.count == 4, "Original source admission oracle failed.")
            for (bound, value) in zip(forward, [expected, 0, expected, 0]) { try SourceDirectAdmissionChecks.require(bound.contains(value), "Original source admission oracle failed.") }
            let reversed = try run(OriginalQueryBudget(), direction: .reversed)
            for (bound, value) in zip(reversed, [-expected, 0, -expected, 0]) { try SourceDirectAdmissionChecks.require(bound.contains(value), "Original source admission oracle failed.") }
            let exact = try OriginalQueryBudget(workLimit: cost.work, storageByteLimit: cost.storageBytes)
            try SourceDirectAdmissionChecks.require(try run(exact) == forward, "Original source admission oracle failed.")
            try SourceDirectAdmissionChecks.require(exact.snapshot.work == cost.work && exact.snapshot.storageBytes == cost.storageBytes, "Original source admission oracle failed.")
            for axis in [ExactResource.work, .storage] {
                let limited = try OriginalQueryBudget(workLimit: axis == .work ? cost.work - 1 : cost.work,
                    storageByteLimit: axis == .storage ? cost.storageBytes - 1 : cost.storageBytes)
                do { _ = try run(limited); throw SourceDirectAdmissionChecks.Failure(detail: "A restricted graph escaped its caller limit.") }
                catch {
                    guard case .resourceLimit(let actual)? = originalError(error) as? ExactScalarFailure else { throw error }
                    try SourceDirectAdmissionChecks.require(actual == axis, "Original source admission oracle failed.")
                }
            }
        }

        private final class Checkpoints: Sendable {
            private let state = Mutex(0)
            let stop: Int?
            init(stop: Int? = nil) { self.stop = stop }
            var count: Int { state.withLock { $0 } }
            func checkpoint() throws {
                let value = state.withLock { count in count += 1; return count }
                if value == stop { throw CancellationError() }
            }
        }

        static func graphReadersPreserveCallerCancellation(restricted: Bool) throws {
            let observing = Checkpoints()
            var normal = try execution(OriginalQueryBudget(checkpoint: { try observing.checkpoint() }))
            _ = try originalQuery(restricted: restricted, using: &normal)
            for stop in [1, observing.count] {
                let checkpoints = Checkpoints(stop: stop)
                var query = try execution(OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() }))
                do {
                    _ = try originalQuery(restricted: restricted, using: &query)
                    throw SourceDirectAdmissionChecks.Failure(detail: "A cancelled original graph reader published bounds.")
                } catch {
                    let cause = originalError(error)
                    if let scalar = cause as? ExactScalarFailure {
                        guard case .cancelled = scalar else { throw error }
                    } else { try SourceDirectAdmissionChecks.require(cause is CancellationError, "Original source admission oracle failed.") }
                }
                try SourceDirectAdmissionChecks.require(checkpoints.count == stop, "Original source admission oracle failed.")
            }
        }

    }
}
