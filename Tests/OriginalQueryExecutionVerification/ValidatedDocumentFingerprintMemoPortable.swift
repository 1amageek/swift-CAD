import CADCore
import CADGeometry
import Synchronization
@testable import CADIR
#if !hasFeature(Embedded)
import Foundation
#endif

/// Exercises the production memo with fingerprints issued by real document encoding.
@main
struct ValidatedDocumentFingerprintMemoPortable {
    private enum ProbeError: Error { case expectedFailure, unexpectedComputation }
    private struct Failure: Error { let line: UInt; let message: String }

    private struct Observation: Sendable {
        var active = 0
        var peak = 0
        var computations = 0
    }

    private final class Activity: Sendable {
        let state = Mutex(Observation())
    }

    private actor StartGate {
        let participants: Int
        var waiters: [CheckedContinuation<Void, Never>] = []

        init(participants: Int) { self.participants = participants }

        func arrive() async {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
                if waiters.count == participants {
                    let ready = waiters
                    waiters.removeAll()
                    for waiter in ready { waiter.resume() }
                }
            }
        }
    }

    private nonisolated static func require(
        _ condition: Bool, _ message: String, line: UInt = #line
    ) throws {
        if !condition { throw Failure(line: line, message: message) }
    }

    private nonisolated static func document(units: UnitSystem) -> CADDocument {
        CADDocument(units: units, metadata: .init(name: "Portable memo",
            createdAtReferenceDate: 0, updatedAtReferenceDate: 0))
    }

    private nonisolated static func currentClock() throws {
        let metadata = try DocumentMetadata.current(name: "Portable clock")
        try metadata.validate()
        try require(metadata.name == "Portable clock"
            && metadata.createdAtReferenceDate.isFinite
            && metadata.createdAtReferenceDate == metadata.updatedAtReferenceDate,
            "One finite UTC clock read must supply both authored timestamps.")
        print("PASS memo actual-platform-clock")
    }

    private nonisolated static func bridgeValueOwnership() throws {
        let firstID = FeatureID(PortableIdentity128(high: 0, low: 1))
        let secondID = FeatureID(PortableIdentity128(high: 0, low: 2))
        let bridgeID = FeatureID(PortableIdentity128(high: 0, low: 3))
        let signature = try SubshapeGeometrySignature.lineEdge(
            startPoint: .origin, endPoint: .init(x: 1, y: 0, z: 0))
        let first = StableSubshapeReference(subshapeID: .init(featureID: firstID, role: "edge", ordinal: 0),
            geometrySignature: signature)
        let second = StableSubshapeReference(subshapeID: .init(featureID: secondID, role: "edge", ordinal: 0),
            geometrySignature: signature)
        let payload = BridgeSurfaceFeature(startBoundary: first, endBoundary: second)
        let operation = FeatureOperation.bridgeSurface(payload)
        let copy = operation
        let rebuilt = FeatureOperation.bridgeSurface(payload)
        let changed = FeatureOperation.bridgeSurface(.init(startBoundary: first, endBoundary: second,
            startTension: 2))
        try require(operation == copy && copy == rebuilt && operation != changed
            && Set([operation, copy, rebuilt]).count == 1 && Set([copy, changed]).count == 2,
            "Retained and independently constructed bridge payloads must preserve value equality and hashing.")
        guard case .bridgeSurface(let retained) = copy else {
            throw Failure(line: #line, message: "The copied operation must retain its actual bridge case.")
        }
        try require(retained.startBoundary == first && retained.endBoundary == second
            && retained.startTension == 1, "Replacing a bridge value must not mutate a retained copy.")
        func source(_ value: FeatureOperation) -> CADDocument {
            let box = PrimitiveFeature(definition: .box(.init(width: .constant(.length(1, unit: .meter)),
                depth: .constant(.length(1, unit: .meter)), height: .constant(.length(1, unit: .meter)))))
            let firstNode = FeatureNode(id: firstID, operation: .primitive(box), outputs: [.init(role: .body)])
            let secondNode = FeatureNode(id: secondID, operation: .primitive(box), outputs: [.init(role: .body)])
            let bridgeNode = FeatureNode(id: bridgeID, operation: value, inputs: payload.sourceInputs,
                outputs: [.init(role: .sheet)])
            return CADDocument(units: .meters, designGraph: .init(
                nodes: [firstID: firstNode, secondID: secondNode, bridgeID: bridgeNode],
                order: [firstID, secondID, bridgeID], dependencies: bridgeNode.inputDependencyEdges),
                metadata: .init(createdAtReferenceDate: 0, updatedAtReferenceDate: 0))
        }
        let fingerprint = try source(operation).sourceFingerprint(tolerance: .standard)
        try require(try source(rebuilt).sourceFingerprint(tolerance: .standard) == fingerprint
            && source(changed).sourceFingerprint(tolerance: .standard) != fingerprint,
            "Source fingerprint identity must follow original bridge fields, not box identity.")
#if !hasFeature(Embedded)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(operation)
        let expected = Data(("{\"bridgeSurface\":" + String(decoding: try encoder.encode(payload), as: UTF8.self)
            + ",\"kind\":\"bridgeSurface\"}").utf8)
        try require(encoded == expected && encoded == encoder.encode(copy),
            "The existing bridge kind and payload wire framing must remain byte exact.")
        try require(try JSONDecoder().decode(FeatureOperation.self, from: encoded) == operation,
            "The actual Native bridge codec must retain its source value.")
#endif
        print("PASS memo bridge-value hash-codec-source-identity")
    }

    private nonisolated static func sketchOrdering() throws {
        let id = SketchEntityID(PortableIdentity128(high: 0, low: 1))
        let resolver = SketchCurveChainResolver()
        let references: [SketchReference] = [.entity(id), .lineStart(id), .lineEnd(id), .circleCenter(id),
            .circleRadius(id), .arcCenter(id), .arcStart(id), .arcEnd(id), .arcRadius(id),
            .splineControlPoint(entity: id, index: 2)]
        let names = ["entity", "lineStart", "lineEnd", "circleCenter", "circleRadius", "arcCenter",
            "arcStart", "arcEnd", "arcRadius"]
        let expected = names.map { "\($0)(00000000-0000-0000-0000-000000000001)" }
            + ["splineControlPoint(entity: 00000000-0000-0000-0000-000000000001, index: 2)"]
        try require(references.map { resolver.stableReferenceName($0) } == expected,
            "All ten keys must retain the measured original Native strings.")
        let ordered = references.sorted { resolver.stableReferenceName($0) < resolver.stableReferenceName($1) }
        try require(ordered == [.arcCenter(id), .arcEnd(id), .arcRadius(id), .arcStart(id),
            .circleCenter(id), .circleRadius(id), .entity(id), .lineEnd(id), .lineStart(id),
            .splineControlPoint(entity: id, index: 2)], "Portable keys must preserve original lexical order.")
        let arcID = SketchEntityID(PortableIdentity128(high: 0, low: 2))
        func point(_ x: Double, _ y: Double) -> SketchPoint {
            .init(x: .constant(.length(x, unit: .meter)), y: .constant(.length(y, unit: .meter)))
        }
        let sketch = Sketch(plane: .xy, entities: [
            id: .line(.init(start: point(0, 0), end: point(0.01, 0))),
            arcID: .arc(.init(center: point(0.01, 0.005), radius: .constant(.length(0.005, unit: .meter)),
                startAngle: .constant(.angle(-90, unit: .degree)), endAngle: .constant(.angle(0, unit: .degree))))],
            constraints: [.coincident(.lineEnd(id), .arcStart(arcID))])
        let chain = try resolver.resolveOpenChain(in: sketch, selectedEntityID: id)
        try require(chain.segments == [.init(entityID: id, startReference: .lineStart(id), endReference: .lineEnd(id)),
            .init(entityID: arcID, startReference: .arcStart(arcID), endReference: .arcEnd(arcID))]
            && chain.vertices.count == 3
            && chain.vertices[1].connectedEndpointReferences == [.arcStart(arcID), .lineEnd(id)],
            "The real connected line/arc chain must retain traversal and ordered shared references.")
        print("PASS memo sketch-reference-keys actual-chain-order")
    }

    private nonisolated static func documentCancellation() async throws {
        let source = document(units: .meters)
        let reference = DocumentObjectReference(documentID: source.id)
        let resolver = DefaultDocumentReferenceResolver()
        try DocumentAttributeValue.reals([1]).validate()
        guard case .document(let resolved) = try resolver.resolve(reference,
            in: [source.id: source], tolerance: .standard), resolved.id == source.id else {
            throw Failure(line: #line, message: "The original resolver must resolve its real document.")
        }
        try await withThrowingTaskGroup(of: Int.self) { group in
            group.cancelAll()
            group.addTask {
                var refusals = 0
                do { try DocumentAttributeValue.reals([1]).validate() }
                catch is CancellationError { refusals += 1 }
                do { _ = try resolver.resolve(reference, in: [source.id: source], tolerance: .standard) }
                catch is CancellationError { refusals += 1 }
                return refusals
            }
            try require(try await group.next() == 2,
                "A genuinely cancelled child must retain loop and resolver-entry cancellation failures.")
        }
        print("PASS memo actual-document-cancellation")
    }

    private nonisolated static func boundaryMath() throws {
        func side(slope: Double) -> SurfaceContinuitySamplingSide {
            let surface = BSplineSurface3D.bilinearPatch(bottomLeft: .origin,
                bottomRight: Point3D(x: 1, y: 0, z: 0), topRight: Point3D(x: 1, y: 1, z: slope),
                topLeft: Point3D(x: 0, y: 1, z: slope))
            return .init(surface: .bSpline(surface), parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1))
        }
        let evaluator = SurfaceBoundaryContinuityEvaluator(modelingTolerance: .standard)
        let tolerances = SurfaceContinuityTolerances(positionDistance: 1e-7,
            normalAngle: 0.01, principalCurvature: 1e-5)
        let flat = side(slope: 0), tilted = side(slope: 0.1)
        var execution = try OriginalQueryExecution.independentGeometry()
        let tangent = try evaluator.certify(first: flat, second: flat, requiredLevel: .tangentPlane,
            tolerances: tolerances, maximumIntervals: 100, maximumDepth: 10, using: &execution)
        guard let angle = tangent.maximumNormalAngle else {
            throw Failure(line: #line, message: "Tangent-plane continuity must retain its normal-angle bound.")
        }
        try require(tangent.level == .tangentPlane && tangent.inspectedIntervals > 0
            && tangent.maximumPositionDistance <= tolerances.positionDistance
            && angle.isFinite && angle <= tolerances.normalAngle,
            "The original same-patch boundary must obtain its complete tangent-plane certificate.")
        let position = try evaluator.certify(first: flat, second: tilted, requiredLevel: .positional,
            tolerances: tolerances, maximumIntervals: 100, maximumDepth: 10, using: &execution)
        try require(position.level == .positional && position.maximumNormalAngle == nil
            && position.maximumPositionDistance <= tolerances.positionDistance,
            "The tilted support must retain position continuity on its authored common edge.")
        do {
            _ = try evaluator.certify(first: flat, second: tilted, requiredLevel: .tangentPlane,
                tolerances: tolerances, maximumIntervals: 100, maximumDepth: 10, using: &execution)
            throw Failure(line: #line, message: "The tilted support must fail its stricter angle request.")
        } catch let error as KernelError {
            try require(error.code == .classificationFailure,
                "The original normal-angle violation must remain a classification failure.")
        }
        print("PASS memo actual-boundary-math certificate-angle-refusal")
    }

    private nonisolated static func failureRetryAndReuse(
        _ fingerprint: CADDocumentSourceFingerprint
    ) throws {
        let memo = ValidatedCADDocumentSourceFingerprintMemo()
        try require(!memo.hasValue, "A new memo must be empty.")
        var computations = 0
        do {
            _ = try memo.value {
                computations += 1
                throw ProbeError.expectedFailure
            }
            throw Failure(line: #line, message: "The original computation must fail.")
        } catch ProbeError.expectedFailure {}
        try require(!memo.hasValue && computations == 1, "A failed computation must store nothing.")
        let retried = try memo.value { computations += 1; return fingerprint }
        try require(memo.hasValue && retried == fingerprint && computations == 2,
            "Retry must publish the completed original fingerprint.")
        let reused = try memo.value { throw ProbeError.unexpectedComputation }
        try require(reused == fingerprint && computations == 2,
            "Reading a completed value must not compute again.")
        print("PASS memo failure-retry completed-reuse")
    }

    private nonisolated static func reentrantFirstPublication(
        first: CADDocumentSourceFingerprint, later: CADDocumentSourceFingerprint
    ) throws {
        let memo = ValidatedCADDocumentSourceFingerprintMemo()
        var outerCalls = 0
        var innerCalls = 0
        let published = try memo.value {
            outerCalls += 1
            try require(!memo.hasValue, "The outer computation has not completed.")
            let inner = try memo.value { innerCalls += 1; return first }
            try require(inner == first && memo.hasValue,
                "Reentrant computation must finish and publish outside the mutex.")
            return later
        }
        try require(published == first && outerCalls == 1 && innerCalls == 1,
            "The first completed publication must win over the outer candidate.")
        try require(try memo.value { throw ProbeError.unexpectedComputation } == first,
            "The first completed value must remain retained.")
        print("PASS memo reentrant-compute first-completed-publication")
    }

    private nonisolated static func retainedReader(
        _ fingerprint: CADDocumentSourceFingerprint
    ) throws -> @Sendable () throws -> CADDocumentSourceFingerprint {
        let memo = ValidatedCADDocumentSourceFingerprintMemo()
        _ = try memo.value { fingerprint }
        return { try memo.value { throw ProbeError.unexpectedComputation } }
    }

    private nonisolated static func taskGroupAccess(
        sources: [CADDocument], expected: [CADDocumentSourceFingerprint]
    ) async throws {
        let participants = 8
        let memo = ValidatedCADDocumentSourceFingerprintMemo()
        let gate = StartGate(participants: participants)
        let observation = Activity()
        var completed: [CADDocumentSourceFingerprint] = []
        try await withThrowingTaskGroup(of: CADDocumentSourceFingerprint.self) { group in
            for index in 0..<participants {
                group.addTask {
                    await gate.arrive()
                    return try memo.value {
                        observation.state.withLock { state in
                            state.active += 1
                            state.peak = max(state.peak, state.active)
                            state.computations += 1
                        }
                        defer { observation.state.withLock { $0.active -= 1 } }
                        return try sources[index % sources.count].sourceFingerprint(tolerance: .standard)
                    }
                }
            }
            while let value = try await group.next() { completed.append(value) }
        }
        let state = observation.state.withLock { $0 }
        try require(completed.count == participants && memo.hasValue,
            "Every task must finish with a completed memo value.")
        let winner = try memo.value { throw ProbeError.unexpectedComputation }
        try require(expected.contains(winner) && completed.allSatisfy { $0 == winner },
            "All readers must observe one original source fingerprint.")
        try require(state.active == 0 && state.computations >= 1 && state.computations <= participants,
            "All actual computations must finish within the declared task count.")
        // Physical overlap is observed independently of target task scheduling support.
        print("PASS memo task-group readers=\(completed.count) computations=\(state.computations) peak-computations=\(state.peak)")
    }

    static func main() async throws {
        try currentClock()
        try boundaryMath()
        try bridgeValueOwnership()
        try sketchOrdering()
        try await documentCancellation()
        let sources = [document(units: .meters), document(units: .millimeters)]
        let first = try sources[0].sourceFingerprint(tolerance: .standard)
        let second = try sources[1].sourceFingerprint(tolerance: .standard)
        try require(first.algorithm == "sha256-cad-source-binary-v1" && first != second,
            "Distinct authored units must issue distinct real source fingerprints.")
        try failureRetryAndReuse(first)
        try reentrantFirstPublication(first: first, later: second)
        let read = try retainedReader(first)
        try require(try read() == first && read() == first,
            "An escaping reader must retain the actual memo and completed owner.")
        print("PASS memo retained-owner")
        try await taskGroupAccess(sources: sources, expected: [first, second])
        print("PASS memo all")
    }
}
