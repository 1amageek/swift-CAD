import CADCore
import CADGeometry
import CADIR
import CADTopology
import HashTreeCollections
import Synchronization
@testable import CADModeling

struct BridgeSurfaceFailureClassificationChecks {
    enum Failure: Error { case mismatch, missingValue, missingRefusal }
    private enum Mode: Sendable, Equatable { case success, work, storage, cancellation }

    private final class Observation: Sendable {
        struct State: Sendable {
            var calls = 0
            var entryWork = 0
            var budget: OriginalQueryBudget?
            var builtSurface: BSplineSurface3D?
            var originalError: (any Error)?
        }
        private let state = Mutex(State())
        func entered(work: Int, budget: OriginalQueryBudget) {
            state.withLock { $0.calls += 1; $0.entryWork = work; $0.budget = budget }
        }
        func built(_ surface: BSplineSurface3D) { state.withLock { $0.builtSurface = surface } }
        func failed(_ error: any Error) { state.withLock { $0.originalError = error } }
        var snapshot: State { state.withLock { $0 } }
    }

    // The protocol witness changes only admission. Every result or refusal comes
    // from the production Geometry builder over the evaluator's real boundaries.
    private struct ForwardingBuilder: RuledBSplineSurfaceBuilding {
        let mode: Mode
        let observation: Observation
        func build(startBoundary: BSplineCurve3D, endBoundary: BSplineCurve3D,
            tolerance: ModelingTolerance) throws -> BSplineSurface3D {
            throw Failure.mismatch
        }
        func build(startBoundary: BSplineCurve3D, endBoundary: BSplineCurve3D,
            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
            let selected: OriginalQueryContributionHandle?
            switch mode {
            case .work: selected = try execution.makeContributionHandle(workLimit: 1)
            case .storage: selected = try execution.makeContributionHandle(storageByteLimit: 0)
            case .success, .cancellation: selected = nil
            }
            if let selected {
                return try execution.withContributionScope(selected) { execution in
                    try original(startBoundary, endBoundary, tolerance: tolerance, using: &execution)
                }
            }
            return try original(startBoundary, endBoundary, tolerance: tolerance, using: &execution)
        }
        private func original(_ first: BSplineCurve3D, _ second: BSplineCurve3D,
            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
            execution.context = execution.context.at(stage: .relation)
            observation.entered(work: execution.budget.snapshot.work, budget: execution.budget)
            do {
                let result = try ExactRuledBSplineSurfaceBuilder().build(startBoundary: first,
                    endBoundary: second, tolerance: tolerance, using: &execution)
                observation.built(result)
                return result
            } catch {
                observation.failed(error)
                throw error
            }
        }
    }

    private static func require(_ condition: Bool) throws {
        guard condition else { throw Failure.mismatch }
    }
    private static func value<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw Failure.missingValue }
        return value
    }
    private static let sourceID = FeatureID(PortableIdentity128(high: 203, low: 1))
    private static let featureID = FeatureID(PortableIdentity128(high: 203, low: 2))

    @inline(never)
    private static func fixture() throws -> (FeatureNode, EvaluationContext) {
        // Public authored topology, not a synthesized validation/cache receipt.
        // Every spatial edge is the exact lift of its actual plane-face chart.
        let surface = Surface3D.plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX))
        let points: [Point3D] = [.origin, .init(x: 1, y: 0, z: 0),
            .init(x: 1, y: 1, z: 0), .init(x: 0, y: 1, z: 0)]
        let charts: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 0, uEnd: 1),
            .constantU(u: 1, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 1, uEnd: 0),
            .constantU(u: 0, vStart: 1, vEnd: 0)]
        let bodyID = BodyID(PortableIdentity128(high: 204, low: 1))
        let shellID = ShellID(PortableIdentity128(high: 205, low: 1))
        let faceID = FaceID(PortableIdentity128(high: 206, low: 1))
        let surfaceID = SurfaceID(PortableIdentity128(high: 207, low: 1))
        let loopID = LoopID(PortableIdentity128(high: 208, low: 1))
        let vertexIDs = (1...4).map { VertexID(PortableIdentity128(high: 209, low: UInt64($0))) }
        let edgeIDs = (1...4).map { EdgeID(PortableIdentity128(high: 210, low: UInt64($0))) }
        let curveIDs = (1...4).map { CurveID(PortableIdentity128(high: 211, low: UInt64($0))) }
        var model = BRepModel(geometry: .init(surfaces: [surfaceID: surface]),
            bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, coedges: edgeIDs.enumerated().map {
                Coedge(edgeID: $0.element, surfaceParameterCurve: charts[$0.offset])
            })])
        var entries: [SubshapeID: TopologyReference] = [
            SubshapeID(featureID: sourceID, role: "body", ordinal: 0): .body(bodyID)]
        for index in points.indices {
            model.vertices[vertexIDs[index]] = Vertex(id: vertexIDs[index], point: points[index])
            model.geometry.curves[curveIDs[index]] = .surfaceLift(.init(surface: surface,
                parameterCurve: charts[index]))
            model.edges[edgeIDs[index]] = Edge(id: edgeIDs[index], curveID: curveIDs[index],
                startVertexID: vertexIDs[index], endVertexID: vertexIDs[(index + 1) % 4],
                trim: .init(startParameter: 0, endParameter: 1))
            entries[SubshapeID(featureID: sourceID, role: "edge", ordinal: index)] = .edge(edgeIDs[index])
        }
        let start = StableSubshapeReference(subshapeID: .init(featureID: sourceID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(startPoint: points[0], endPoint: points[1]))
        let end = StableSubshapeReference(subshapeID: .init(featureID: sourceID, role: "edge", ordinal: 2),
            geometrySignature: try .lineEdge(startPoint: points[2], endPoint: points[3]))
        let feature = FeatureNode(id: featureID, operation: .bridgeSurface(.init(
            startBoundary: start, endBoundary: end, endOrientation: .reversed)),
            inputs: [FeatureInput(featureID: sourceID, role: .target)], outputs: [.init(role: .sheet)])
        return (feature, EvaluationContext(parameters: .init(), brep: model, profiles: [:],
            subshapes: SubshapeIndex(entries), tolerance: .standard))
    }

    private static func execution(mode: Mode, observation: Observation) throws -> OriginalQueryExecution {
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
            checkpoint: {
                if mode == .cancellation, observation.snapshot.calls > 0 { throw CancellationError() }
            })
        return OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .conversion, entry: .admitted, stage: .request))
    }

    static func actualRuledBuilderPublishesANonemptyBridge() throws {
        let (feature, context) = try fixture()
        let observation = Observation()
        var execution = try execution(mode: .success, observation: observation)
        let result = try BridgeSurfaceFeatureEvaluator(surfaceBuilder:
            ForwardingBuilder(mode: .success, observation: observation))
            .evaluateValidated(feature: feature, context: context, using: &execution).result
        let recorded = observation.snapshot
        try require(recorded.budget === execution.budget)
        try require(recorded.calls == 1 && recorded.entryWork > 0 && recorded.originalError == nil)
        let surface = try value(recorded.builtSurface)
        try require(surface.uDegree == 1 && surface.vDegree == 1)
        try require(try surface.point(u: 0.25, v: 0.75, tolerance: .standard,
            using: &execution) == Point3D(x: 0.25, y: 0.75, z: 0))
        try require(result.brep.bodies.count == 2 && result.brep.faces.count == 2)
        try require(result.brep.edges.count == 8 && result.brep.vertices.count == 8)
        for (id, face) in context.brep.faces { try require(result.brep.faces[id] == face) }
        for (id, edge) in context.brep.edges { try require(result.brep.edges[id] == edge) }
        try require(execution.budget.snapshot.work > recorded.entryWork)
    }

    static func actualRuledBuilderWorkRefusalKeepsItsCauseAndFeatureContext() throws {
        try resourceRefusal(.work)
    }
    static func actualRuledBuilderStorageRefusalKeepsItsCauseAndFeatureContext() throws {
        try resourceRefusal(.storage)
    }
    private static func resourceRefusal(_ mode: Mode) throws {
        let (feature, context) = try fixture()
        let observation = Observation()
        var execution = try execution(mode: mode, observation: observation)
        do {
            _ = try BridgeSurfaceFeatureEvaluator(surfaceBuilder:
                ForwardingBuilder(mode: mode, observation: observation))
                .evaluateValidated(feature: feature, context: context, using: &execution)
        } catch {
            let recorded = observation.snapshot
            try require(recorded.budget === execution.budget)
            try require(recorded.calls == 1 && recorded.entryWork > 0 && recorded.builtSurface == nil)
            let raw = try value(recorded.originalError as? ExactScalarFailure)
            // Budget refusals retain their concrete owner inside admissionRejected;
            // Geometry publication exposes that owner's original scalar cause.
            guard case .admissionRejected(let ownedCause) = raw else { throw Failure.mismatch }
            let lower = try value(ownedCause as? OriginalQueryFailure)
            let lowerScalar = try value(lower.originalError as? ExactScalarFailure)
            let failure = try value(error as? OriginalQueryFailure)
            let retained = try value(failure.originalError as? ExactScalarFailure)
            try require(lower.kernelFailure.phase == .geometry)
            try require(lower.kernelFailure.code == .resourceLimitExceeded)
            try require(failure.context.operation == lower.context.operation)
            try require(failure.context.entry == lower.context.entry)
            try require(failure.context.stage == lower.context.stage)
            try require(failure.context.resource == lower.context.resource)
            switch (mode, lowerScalar, retained) {
            case (.work, .resourceLimit(.work), .resourceLimit(.work)):
                try require(failure.context.resource?.axis == .work)
                try require(execution.budget.snapshot.work == recorded.entryWork + 1)
            case (.storage, .resourceLimit(.storage), .resourceLimit(.storage)):
                try require(failure.context.resource?.axis == .storageBytes)
                try require(execution.budget.snapshot.work > recorded.entryWork)
            default: throw Failure.mismatch
            }
            try require(failure.kernelFailure.phase == .geometry)
            try require(failure.kernelFailure.code == .resourceLimitExceeded)
            try require(failure.kernelFailure.featureID == featureID)
            try require(failure.kernelFailure.tolerance == .standard)
            try require(failure.context.operation == .conversion && failure.context.entry == .admitted)
            try require(failure.context.stage == .relation)
            return
        }
        throw Failure.missingRefusal
    }

    static func actualRuledBuilderCancellationKeepsItsCause() throws {
        let (feature, context) = try fixture()
        let observation = Observation()
        var execution = try execution(mode: .cancellation, observation: observation)
        do {
            _ = try BridgeSurfaceFeatureEvaluator(surfaceBuilder:
                ForwardingBuilder(mode: .cancellation, observation: observation))
                .evaluateValidated(feature: feature, context: context, using: &execution)
        } catch {
            let recorded = observation.snapshot
            try require(recorded.budget === execution.budget)
            try require(recorded.calls == 1 && recorded.entryWork > 0 && recorded.builtSurface == nil)
            try require(recorded.originalError != nil)
            try require(error is CancellationError)
            try require(execution.context.stage == .relation)
            try require(execution.budget.snapshot.work == recorded.entryWork)
            return
        }
        throw Failure.missingRefusal
    }
}
