import Foundation
import Synchronization
import Testing
import CADCore
import CADGeometry
import CADIR
@testable import CADExchange

@Suite("Independent graph original owner binding", .timeLimit(.minutes(1)))
struct IndependentGraphOwnerBindingTests {
    private enum UnexpectedCall: Error, Equatable { case producer, appendAfterMutation, finishAfterMutation }
    private final class Observations: Sendable {
        private struct State { var fields = 0; var producers = 0 }
        private let state = Mutex(State())
        var fieldCalls: Int { state.withLock { $0.fields } }
        var producerCalls: Int { state.withLock { $0.producers } }
        func field() { state.withLock { $0.fields += 1 } }
        func rejectProducer() -> UnexpectedCall {
            state.withLock { $0.producers += 1 }
            return .producer
        }
    }

    private struct Fields: STEPFieldReading {
        let observations: Observations
        // Original #50 wire from IndependentShapeExchangeTests.literalSTEP.
        private let syntax = STEPAssemblySyntax(entities: [50: "GROUP('shared group',$)"])
        init(observations: Observations) { self.observations = observations }
        func entity(_ id: Int) throws -> String { observations.field(); return try syntax.entity(id) }
        func name(_ id: Int) throws -> String { observations.field(); return try syntax.name(id) }
        func hasComponent(_ id: Int, named: String) throws -> Bool { observations.field(); return try syntax.hasComponent(id, named: named) }
        func arguments(_ id: Int, component: String?) throws -> [String] { observations.field(); return try syntax.arguments(id, component: component) }
        func split(_ value: String) throws -> [String] { observations.field(); return try syntax.split(value) }
        func reference(_ value: String) throws -> Int { observations.field(); return try syntax.reference(value) }
        func list(_ value: String) throws -> [Int] { observations.field(); return try syntax.list(value) }
        func string(_ value: String) throws -> String { observations.field(); return try syntax.string(value) }
        func decodedString(_ value: String, limits: STEPStringLimits) throws -> STEPStringResult { observations.field(); return try syntax.decodedString(value, limits: limits) }
        func numbers(_ value: String) throws -> [Double] { observations.field(); return try syntax.numbers(value) }
    }

    private struct UnreachedIGESFields: IndependentIGESFieldReading {
        let observations: Observations
        func entity(_ pointer: Int) throws -> IndependentIGESEntity { observations.field(); throw UnexpectedCall.producer }
        func string(_ token: String) throws -> String { observations.field(); throw UnexpectedCall.producer }
        func integer(_ token: String) throws -> Int { observations.field(); throw UnexpectedCall.producer }
        func number(_ token: String) throws -> Double { observations.field(); throw UnexpectedCall.producer }
    }

    /// Primitive calls always fail; optional real GROUP table state tests lexical writeback only.
    private struct UnreachedProducer: IndependentSTEPGeometryReading, IndependentSTEPGeometryWriting,
        IndependentIGESGeometryReading, IndependentIGESGeometryWriting {
        let observations: Observations
        var groupTable: ExactSTEPWriter.EntityTable? = nil
        var failureAfterMutation: UnexpectedCall? = nil
        mutating func curve(entityID: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, tolerance: ModelingTolerance, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentExchangeReadCurve { throw observations.rejectProducer() }
        mutating func surface(entityID: Int, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, tolerance: ModelingTolerance, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentExchangeReadSurface { throw observations.rejectProducer() }
        mutating func contextLengthSource(entityID: Int, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalSTEPLengthSource { throw observations.rejectProducer() }
        mutating func contextAngularSource(entityID: Int, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentShapeAngularSource { throw observations.rejectProducer() }
        mutating func contextUnits(entityID: Int, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> UnitSystem { throw observations.rejectProducer() }
        mutating func mappingSource(entityID: Int, units: UnitSystem, originalLengthSource: OriginalSTEPLengthSource?, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> OriginalSTEPPlacementSource { throw observations.rejectProducer() }
        mutating func mappingOrigin(entityID: Int, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D { throw observations.rejectProducer() }
        mutating func mappingTarget(entityID: Int, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D { throw observations.rejectProducer() }
        mutating func standaloneUnits(_ units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func context(_ context: IndependentShapeContext, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func curve(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, positionEntityID: Int?, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func surface(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem, originalAngularSource: IndependentShapeAngularSource?, originalLengthSource: OriginalSTEPLengthSource?, positionEntityID: Int?, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func mappingOrigin(_ frame: AffineTransform3D, originalSource: OriginalSTEPPlacementSource?, name: String, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func mappingTarget(_ frame: AffineTransform3D, originalSource: OriginalSTEPPlacementSource?, name: String, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func quotedString(_ value: String, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> String {
            guard groupTable != nil else { throw observations.rejectProducer() }
            return try groupTable!.quotedString(value, using: &execution)
        }
        mutating func appendEntity(_ expression: String, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int {
            guard groupTable != nil else { throw observations.rejectProducer() }
            let entity = try groupTable!.add(expression, using: &execution)
            if failureAfterMutation == .appendAfterMutation {
                failureAfterMutation = nil
                throw UnexpectedCall.appendAfterMutation
            }
            return entity
        }
        mutating func finish(usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Data {
            guard let groupTable else { throw observations.rejectProducer() }
            let output = DataByteSink()
            try ExactSTEPWriter(resourceLimits: usage.limits, tolerance: .standard)
                .publish(table: groupTable, to: output, using: &execution)
            if failureAfterMutation == .finishAfterMutation {
                failureAfterMutation = nil
                throw UnexpectedCall.finishAfterMutation
            }
            return output.bytes
        }
        mutating func curve(entityPointer: Int, units: UnitSystem, tolerance: ModelingTolerance, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentExchangeReadCurve { throw observations.rejectProducer() }
        mutating func surface(entityPointer: Int, units: UnitSystem, tolerance: ModelingTolerance, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> IndependentExchangeReadSurface { throw observations.rejectProducer() }
        mutating func transformation(entityPointer: Int, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D { throw observations.rejectProducer() }
        mutating func instancePlacement(entityPointer: Int, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> AffineTransform3D { throw observations.rejectProducer() }
        mutating func curve(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func surface(_ item: IndependentShapeItem, source: IndependentShapeSource, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func frame(_ frame: IndependentShapeFrame, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func instancePlacement(_ instance: IndependentShapeInstance, definitionPointer: Int, units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func appendEntity(type: Int, form: Int, label: String, transformationPointer: Int, parameters: [String], usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Int { throw observations.rejectProducer() }
        mutating func appendGroupBackPointer(groupPointer: Int, memberPointer: Int, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws { throw observations.rejectProducer() }
        mutating func string(_ value: String, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> String { throw observations.rejectProducer() }
        mutating func finish(units: UnitSystem, usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Data { throw observations.rejectProducer() }
    }

    private func readGroup() throws -> IndependentShapeSource {
        let owner = try IndependentShapeExchangeOwner(limits: .standard)
        var execution = try owner.execution()
        return try readGroup(owner: owner, observations: Observations(), using: &execution)
    }

    private func readGroup(owner: IndependentShapeExchangeOwner, observations: Observations,
        using execution: inout OriginalQueryExecution) throws -> IndependentShapeSource {
        var producer: any IndependentSTEPGeometryReading = UnreachedProducer(observations: observations)
        let result = try DefaultIndependentSTEPGraphReader().read(entityIDs: [50],
            standaloneItemEntityIDs: [], fields: Fields(observations: observations),
            standaloneUnits: .meters, tolerance: .standard,
            producer: &producer, usage: owner, using: &execution)
        let source = try #require(result)
        #expect(source.originalSTEPGroups.count == 1)
        #expect(source.originalSTEPGroups.first?.name == "shared group")
        #expect(source.originalSTEPGroups.first?.description == nil)
        #expect(source.items.isEmpty && source.roots.isEmpty)
        #expect(observations.fieldCalls > 0 && observations.producerCalls == 0)
        #expect(owner.consumedWork > 0)
        let actualBudget = execution.budget
        #expect(actualBudget === owner.originalBudget)
        return source
    }

    private func assertForeignRefusal(owner: IndependentShapeExchangeOwner,
        foreign: OriginalQueryBudget, observations: Observations,
        _ operation: () throws -> Void) {
        let ownerBefore = owner.originalBudget.snapshot
        let foreignBefore = foreign.snapshot
        do {
            try operation()
            Issue.record("A foreign graph execution must be rejected before processing.")
        } catch IndependentShapeExchangeError.invalidAssociation(let message) {
            #expect(message == "Independent graph processing requires its actual exchange owner.")
        } catch {
            Issue.record("Graph owner binding returned an unexpected typed failure: \(error)")
        }
        let ownerAfter = owner.originalBudget.snapshot
        let foreignAfter = foreign.snapshot
        #expect(ownerAfter.work == ownerBefore.work)
        #expect(ownerAfter.storageBytes == ownerBefore.storageBytes)
        #expect(ownerAfter.sourceTextBytes == ownerBefore.sourceTextBytes)
        #expect(ownerAfter.records == ownerBefore.records)
        #expect(foreignAfter.work == foreignBefore.work)
        #expect(foreignAfter.storageBytes == foreignBefore.storageBytes)
        #expect(foreignAfter.sourceTextBytes == foreignBefore.sourceTextBytes)
        #expect(foreignAfter.records == foreignBefore.records)
        #expect(observations.fieldCalls == 0 && observations.producerCalls == 0)
    }

    private func foreignExecution() throws -> OriginalQueryExecution {
        try .init(budget: OriginalQueryBudget(workLimit: 0, storageByteLimit: 0),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    }

    @Test func sameOwnerRetainsTheActualOriginalGroupWithoutPrimitiveCalls() throws {
        _ = try readGroup()
    }

    private func isWorkRefusal(_ error: any Error) -> Bool {
        if let format = error as? IndependentShapeExchangeError,
            case .resourceLimitExceeded(let message) = format {
            return message == "Independent exchange cumulative caller ceiling."
        }
        if let source = error as? IndependentShapeSourceError,
            case .resourceLimitExceeded(let message) = source {
            return message == "Independent source cumulative work ceiling."
        }
        if let failure = error as? OriginalQueryFailure {
            return (failure.kernelFailure.code == .resourceLimitExceeded
                && failure.context.resource?.axis == .work) || isWorkRefusal(failure.originalError)
        }
        if let scalar = error as? ExactScalarFailure {
            switch scalar {
            case .resourceLimit(.work): return true
            case .admissionRejected(let original): return isWorkRefusal(original)
            default: return false
            }
        }
        return false
    }

    @Test func matchedZeroWorkContributionRefusesBeforeFieldsOrSourceMutation() throws {
        let owner = try IndependentShapeExchangeOwner(limits: .standard)
        var execution = try owner.execution()
        let handle = try execution.makeContributionHandle(workLimit: 0)
        let observations = Observations()
        try execution.withContributionScope(handle) { execution in
            let before = owner.originalBudget.snapshot
            let selectedBefore = handle.snapshot
            do {
                _ = try readGroup(owner: owner, observations: observations, using: &execution)
                Issue.record("A zero-work selected graph query must refuse before reading its wire.")
            } catch IndependentShapeExchangeError.resourceLimitExceeded(let message) {
                #expect(message == "Independent exchange cumulative caller ceiling.")
            } catch {
                Issue.record("Selected graph source admission returned an unexpected typed failure: \(error)")
            }
            let after = owner.originalBudget.snapshot
            let selectedAfter = handle.snapshot
            #expect(after.work == before.work && after.storageBytes == before.storageBytes)
            #expect(after.records == before.records && after.sourceTextBytes == before.sourceTextBytes)
            #expect(selectedAfter.work == selectedBefore.work)
            #expect(selectedAfter.records == selectedBefore.records)
            #expect(selectedAfter.storageBytes == selectedBefore.storageBytes)
            #expect(selectedAfter.sourceTextBytes == selectedBefore.sourceTextBytes)
            #expect(observations.fieldCalls == 0 && observations.producerCalls == 0)
        }
    }

    @Test func selectedGroupChargesIncludeTheEntireLexicalPathAtExactWorkBoundary() throws {
        let owner = try IndependentShapeExchangeOwner(limits: .standard)
        var execution = try owner.execution()
        let handle = try execution.makeContributionHandle()
        let observations = Observations()
        try execution.withContributionScope(handle) { execution in
            let before = owner.originalBudget.snapshot
            let selectedBefore = handle.snapshot
            _ = try readGroup(owner: owner, observations: observations, using: &execution)
            let after = owner.originalBudget.snapshot
            let selectedAfter = handle.snapshot
            #expect(after.work - before.work == selectedAfter.work - selectedBefore.work)
            #expect(after.storageBytes - before.storageBytes == selectedAfter.storageBytes - selectedBefore.storageBytes)
            #expect(after.records - before.records == selectedAfter.records - selectedBefore.records)
            #expect(after.sourceTextBytes - before.sourceTextBytes == selectedAfter.sourceTextBytes - selectedBefore.sourceTextBytes)
        }
        let n = handle.snapshot.work
        #expect(n > 0 && observations.fieldCalls > 0)

        let exactOwner = try IndependentShapeExchangeOwner(limits: .standard)
        var exactExecution = try exactOwner.execution()
        let exactHandle = try exactExecution.makeContributionHandle(workLimit: n)
        try exactExecution.withContributionScope(exactHandle) { execution in
            _ = try readGroup(owner: exactOwner, observations: Observations(), using: &execution)
        }
        #expect(exactHandle.snapshot.work == n)

        let insufficientOwner = try IndependentShapeExchangeOwner(limits: .standard)
        var insufficientExecution = try insufficientOwner.execution()
        let insufficientHandle = try insufficientExecution.makeContributionHandle(workLimit: n - 1)
        let insufficientObservations = Observations()
        var returned = false
        do {
            try insufficientExecution.withContributionScope(insufficientHandle) { execution in
                _ = try readGroup(owner: insufficientOwner, observations: insufficientObservations, using: &execution)
                returned = true
            }
            Issue.record("N-1 selected work must not publish a GROUP source.")
        } catch {
            #expect(isWorkRefusal(error))
        }
        #expect(!returned)
        #expect(insufficientHandle.snapshot.work <= n - 1)
        #expect(insufficientOwner.consumedWork == insufficientHandle.snapshot.work)
        #expect(insufficientObservations.producerCalls == 0)
    }

    @Test func realGroupWriterRestoresProducerOnSuccessAppendFailureAndFinishFailure() throws {
        let source = try readGroup()
        let cases: [UnexpectedCall?] = [nil, .appendAfterMutation, .finishAfterMutation]
        for failure in cases {
            let owner = try IndependentShapeExchangeOwner(limits: .standard)
            var execution = try owner.execution()
            let actualBudget = execution.budget
            let observations = Observations()
            var table = try ExactSTEPWriter.EntityTable(maximumEntities: owner.limits.maximumEntities,
                tolerance: .standard, maximumBytes: owner.limits.maximumBytes,
                maximumStringWork: owner.limits.maximumIterations, originalBudget: owner.originalBudget)
            table.independentUsage = owner
            var producer: any IndependentSTEPGeometryWriting = UnreachedProducer(
                observations: observations, groupTable: table, failureAfterMutation: failure)
            var published: Data?
            do {
                published = try DefaultIndependentSTEPGraphWriter().write(source, standaloneUnits: .meters,
                    tolerance: .standard, producer: &producer, usage: owner, using: &execution)
                #expect(failure == nil)
            } catch let actual as UnexpectedCall {
                #expect(actual == failure)
            }
            #expect((published != nil) == (failure == nil))
            // A second real publication observes producer value writeback, not a shared observer.
            let retained = try producer.finish(usage: owner, using: &execution)
            let text = try #require(String(data: retained, encoding: .utf8))
            #expect(text.contains("#1=GROUP('shared group',$);"))
            if let published { #expect(published == retained) }
            #expect(observations.producerCalls == 0)
            let restoredBudget = execution.budget
            #expect(restoredBudget === actualBudget && restoredBudget === owner.originalBudget)
            try execution.consumeWork(1)
        }
    }

    @Test func foreignSTEPReadRejectsBeforeLexicalOrProducerCalls() throws {
        let owner = try IndependentShapeExchangeOwner(limits: .standard)
        var execution = try foreignExecution()
        let foreign = execution.budget
        let observations = Observations()
        var producer: any IndependentSTEPGeometryReading = UnreachedProducer(observations: observations)
        assertForeignRefusal(owner: owner, foreign: foreign, observations: observations) {
            _ = try DefaultIndependentSTEPGraphReader().read(entityIDs: [50],
                standaloneItemEntityIDs: [], fields: Fields(observations: observations),
                standaloneUnits: .meters, tolerance: .standard,
                producer: &producer, usage: owner, using: &execution)
        }
    }

    @Test func foreignIGESReadRejectsBeforeLexicalOrProducerCalls() throws {
        let owner = try IndependentShapeExchangeOwner(limits: .standard, format: .iges)
        var execution = try foreignExecution()
        let foreign = execution.budget
        let observations = Observations()
        var producer: any IndependentIGESGeometryReading = UnreachedProducer(observations: observations)
        assertForeignRefusal(owner: owner, foreign: foreign, observations: observations) {
            _ = try DefaultIndependentIGESGraphReader().read(entityPointers: [],
                standaloneItemPointers: [], fields: UnreachedIGESFields(observations: observations),
                units: .meters, tolerance: .standard,
                producer: &producer, usage: owner, using: &execution)
        }
    }

    @Test func foreignSTEPWriteRejectsBeforeSourceValidationOrProducerCalls() throws {
        let source = try readGroup()
        let owner = try IndependentShapeExchangeOwner(limits: .standard)
        var execution = try foreignExecution()
        let foreign = execution.budget
        let observations = Observations()
        var producer: any IndependentSTEPGeometryWriting = UnreachedProducer(observations: observations)
        assertForeignRefusal(owner: owner, foreign: foreign, observations: observations) {
            _ = try DefaultIndependentSTEPGraphWriter().write(source, standaloneUnits: .meters,
                tolerance: .standard, producer: &producer, usage: owner, using: &execution)
        }
    }

    @Test func foreignSTEPAppendRejectsBeforeSourceValidationOrProducerCalls() throws {
        let source = try readGroup()
        let owner = try IndependentShapeExchangeOwner(limits: .standard)
        var execution = try foreignExecution()
        let foreign = execution.budget
        let observations = Observations()
        var producer = UnreachedProducer(observations: observations)
        assertForeignRefusal(owner: owner, foreign: foreign, observations: observations) {
            try DefaultIndependentSTEPGraphWriter().append(source, standaloneUnits: .meters,
                tolerance: .standard, producer: &producer, usage: owner, using: &execution)
        }
    }

    @Test func foreignIGESWriteRejectsBeforeFormatSemanticsOrProducerCalls() throws {
        let source = try readGroup()
        let owner = try IndependentShapeExchangeOwner(limits: .standard, format: .iges)
        var execution = try foreignExecution()
        let foreign = execution.budget
        let observations = Observations()
        var producer: any IndependentIGESGeometryWriting = UnreachedProducer(observations: observations)
        assertForeignRefusal(owner: owner, foreign: foreign, observations: observations) {
            _ = try DefaultIndependentIGESGraphWriter().write(source, units: .meters,
                tolerance: .standard, producer: &producer, usage: owner, using: &execution)
        }
    }
}
