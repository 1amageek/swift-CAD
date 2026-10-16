import CADCore
import CADGeometry
import CADIR
import CADTopology
import Testing
@testable import CADModeling

@Suite("Feature validation algebra admission", .timeLimit(.minutes(1)))
struct FeatureValidationAlgebraAdmissionTests {
    private enum Entry: CaseIterable, Equatable { case model, receipt, input, publication }

    @inline(never)
    private func sheet(irrationalLengths: Bool = false) -> BRepModel {
        let surface = Surface3D.plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX))
        let uv: [[SurfaceParameter]] = irrationalLengths ? [
            [.init(u: 0, v: 0), .init(u: 1, v: 1), .init(u: 3, v: 2)],
            [.init(u: 3, v: 2), .init(u: 0, v: 3)],
            [.init(u: 0, v: 3), .init(u: 0, v: 0)]
        ] : [
            [.init(u: 0, v: 0), .init(u: 1, v: 0)],
            [.init(u: 1, v: 0), .init(u: 1, v: 1)],
            [.init(u: 1, v: 1), .init(u: 0, v: 1)],
            [.init(u: 0, v: 1), .init(u: 0, v: 0)]
        ]
        let vertices = uv.map { Vertex(point: .init(x: $0[0].u, y: $0[0].v, z: 0)) }
        var curves: [CurveID: Curve3D] = [:], edges: [EdgeID: Edge] = [:], uses: [Coedge] = []
        for index in uv.indices {
            let chart = SurfaceParameterCurve.polyline(uv[index]), curveID = CurveID()
            curves[curveID] = .surfaceLift(.init(surface: surface, parameterCurve: chart))
            let edge = Edge(curveID: curveID, startVertexID: vertices[index].id,
                endVertexID: vertices[(index + 1) % vertices.count].id,
                trim: .init(startParameter: 0, endParameter: 1))
            edges[edge.id] = edge; uses.append(.init(edgeID: edge.id, surfaceParameterCurve: chart))
        }
        let loop = Loop(coedges: uses), surfaceID = SurfaceID()
        let face = Face(surfaceID: surfaceID, loops: [loop.id]), shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        return BRepModel(geometry: .init(curves: curves, surfaces: [surfaceID: surface]),
            bodies: [body.id: body], shells: [shell.id: shell], faces: [face.id: face],
            loops: [loop.id: loop], edges: edges,
            vertices: Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) }))
    }

    private func execution(_ budget: OriginalQueryBudget, coefficientDepth: Int = 32,
        sourceDepth: Int = 32) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: coefficientDepth, remainingSourceDepth: sourceDepth,
            maximumSubdivisionDepth: 32, maximumSpans: 64))
    }

    @inline(never)
    private func validate(_ entry: Entry, _ model: BRepModel,
        using execution: inout OriginalQueryExecution) throws {
        switch entry {
        case .model: try model.validate(level: .exact, tolerance: .standard, using: &execution)
        case .receipt:
            let receipt = try ValidatedBRepModel(model, tolerance: .standard, using: &execution)
            #expect(receipt.validationLevel == .exact && receipt.model.faces.count == 1)
        case .input:
            try FeatureEvaluationBoundary.validateExactInput(model, featureID: FeatureID(),
                tolerance: .standard, using: &execution)
        case .publication:
            let receipt = try ValidatedFeatureEvaluation(validating: .init(brep: model),
                tolerance: .standard, using: &execution)
            #expect(receipt.brep.validationLevel == .exact && receipt.result.brep.faces.count == 1)
        }
    }

    private func retained(_ error: any Error) -> OriginalQueryFailure? {
        if let failure = error as? OriginalQueryFailure { return failure }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return retained(cause)
        }
        return nil
    }

    private func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return original(cause)
        }
        return error
    }

    private func expectResource(_ axis: OriginalQueryResourceAxis, entry: Entry,
        _ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            let failure = retained(error)
            if let scalar = original(error) as? ExactScalarFailure, case .resourceLimit(let actual) = scalar {
                // Direct scalar proof scopes may preserve this raw typed cause.
                // An independent coefficient refusal must not match work or value depth.
                let expected: ExactResource
                switch axis {
                case .work: expected = .work
                case .storageBytes: expected = .storage
                case .coefficientDepth: expected = .coefficientDepth
                default: throw error
                }
                #expect(actual == expected)
            } else {
                #expect(axis == .sourceDepth)
                if entry == .model || entry == .receipt {
                    // These conveniences pass caller source0 to the lift's
                    // existing local guard before a child-depth observation.
                    guard let conversion = original(error) as? GeometryConversionError else { throw error }
                    #expect(conversion == .resourceLimitExceeded("Original lift validation exhausted source depth."))
                    #expect(failure == nil)
                } else {
                    // Modeling's existing local source16 still meets the
                    // independent execution source0 ceiling at the first child.
                    let observed = try #require(failure?.context.resource)
                    #expect(observed.axis == .sourceDepth)
                }
            }
            if let failure {
                #expect(failure.kernelFailure.code == .resourceLimitExceeded)
                if let observed = failure.context.resource { #expect(observed.axis == axis) }
            }
            if case .input = entry {
                let published = try #require(failure)
                #expect(published.context.stage == .source)
                #expect(published.kernelFailure.featureID != nil)
            }
            return
        }
        Issue.record("The caller resource ceiling did not refuse source validation.")
    }

    @Test
    func selectedConveniencesKeepIndependentCoefficientWorkBytesSourceAndCancellationLimits() throws {
        let model = sheet(), coefficientWitness = sheet(irrationalLengths: true)
        // The three-point source owns lengths sqrt(2), sqrt(5); it must construct
        // a coefficient root even though value-depth admission independently remains 32.
        for entry in Entry.allCases {
            var measuring = try execution(OriginalQueryBudget(workLimit: 262_144))
            try measuring.consumeWork(7)
            try validate(entry, model, using: &measuring)
            let complete = measuring.budget.snapshot
            #expect(complete.work > 7 && complete.storageBytes > 0)
            var exact = try execution(OriginalQueryBudget(workLimit: complete.work,
                storageByteLimit: complete.storageBytes))
            try exact.consumeWork(7); try validate(entry, model, using: &exact)
            #expect(exact.budget.snapshot.work == complete.work)
            #expect(exact.budget.snapshot.storageBytes == complete.storageBytes)
            var shortWork = try execution(OriginalQueryBudget(workLimit: complete.work - 1))
            try shortWork.consumeWork(7)
            try expectResource(.work, entry: entry) { try validate(entry, model, using: &shortWork) }
            var shortBytes = try execution(OriginalQueryBudget(storageByteLimit: complete.storageBytes - 1))
            try shortBytes.consumeWork(7)
            try expectResource(.storageBytes, entry: entry) { try validate(entry, model, using: &shortBytes) }
            var coefficientZero = try execution(OriginalQueryBudget(workLimit: 262_144), coefficientDepth: 0)
            try expectResource(.coefficientDepth, entry: entry) { try validate(entry, coefficientWitness, using: &coefficientZero) }
            var sourceZero = try execution(OriginalQueryBudget(workLimit: 262_144), sourceDepth: 0)
            try expectResource(.sourceDepth, entry: entry) { try validate(entry, model, using: &sourceZero) }
            var cancelled = try execution(OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled }))
            do {
                try validate(entry, model, using: &cancelled)
                Issue.record("Cancelled source validation published a result.")
            } catch {
                let cause = original(error)
                if let scalar = cause as? ExactScalarFailure, case .cancelled = scalar {
                    // The direct scalar boundary may retain the callback cause.
                } else if !(cause is CancellationError) {
                    throw error
                }
                // Publication deliberately preserves canonical cancellation as a raw cause.
            }
            #expect(cancelled.budget.snapshot.work == 0 && cancelled.budget.snapshot.storageBytes == 0)
        }
    }

    @Test
    func ordinarySelectionDoesNotReplaceExplicitNilOrAuthorizeInvalidSource() throws {
        let model = sheet()
        try model.validate(level: .exact, tolerance: .standard)
        let receipt = try ValidatedBRepModel(model, tolerance: .standard)
        #expect(receipt.validationLevel == .exact)
        for makeReceipt in [false, true] {
            var query = try execution(OriginalQueryBudget(workLimit: 262_144))
            do {
                if makeReceipt {
                    _ = try ValidatedBRepModel(model, tolerance: .standard, maximumSubdivisionDepth: 32,
                        remainingSourceDepth: 16, maximumAlgebraicDepth: nil, using: &query)
                } else {
                    try model.validate(level: .exact, tolerance: .standard, maximumSubdivisionDepth: 32,
                        remainingSourceDepth: 16, maximumAlgebraicDepth: nil, using: &query)
                }
                Issue.record("Explicit bounded nil silently selected an algebra capability.")
            } catch {
                #expect(OriginalQueryFailure.classification(of: error)?.code == .unsupportedCapability)
            }
        }
        var invalid = model
        let vertexID = try #require(invalid.vertices.keys.first)
        let vertex = try #require(invalid.vertices[vertexID])
        invalid.vertices[vertexID] = Vertex(id: vertexID, point: vertex.point + Vector3D(x: 0, y: 0, z: 0.01))
        for entry in Entry.allCases {
            var query = try execution(OriginalQueryBudget(workLimit: 262_144))
            do {
                try validate(entry, invalid, using: &query)
                Issue.record("An endpoint outside its original plane acquired a validation receipt.")
            } catch {
                // validateEdgeGeometry rejects the displaced endpoint with its
                // existing raw TopologyError before pcurve/face publication.
                guard let topology = original(error) as? TopologyError,
                    case .invalidTrim(let edgeID) = topology else { throw error }
                let edge = try #require(invalid.edges[edgeID])
                #expect(edge.startVertexID == vertexID || edge.endVertexID == vertexID)
                if case .input = entry {
                    let published = try #require(retained(error))
                    #expect(published.kernelFailure.code == .topologyFailure)
                    #expect(published.context.stage == .source)
                    #expect(published.kernelFailure.featureID != nil)
                } else {
                    #expect(error as? TopologyError == topology)
                }
            }
        }
    }
}
