import CADCore
import CADGeometry
import CADIR
import CADModeling
import Synchronization
import Testing

@Suite("Parameter expression admission", .timeLimit(.minutes(1)))
struct ParameterExpressionAdmissionTests {
    @Test
    func compoundUnitAwareExpressionsUseTheRequiredWitnessAndOriginalMath() throws {
        let id = ParameterID()
        let parameters = ResolvedParameterTable(values: [id: .length(3, unit: .meter)])
        let expression = CADExpression.divide(
            .add(.hypot(.reference(id), .variable("rise", .length)),
                .multiply(.constant(.length(2, unit: .meter)),
                    .add(.sin(.constant(.angle(.pi / 2, unit: .radian))),
                        .subtract(.cos(.constant(.angle(0, unit: .radian))),
                            .tan(.constant(.angle(0, unit: .radian))))))),
            .constant(.scalar(3)))
        let variables = ["rise": Quantity.length(4, unit: .meter)]
        let resolver: any ParameterResolving = ParameterResolver()
        let budget = try OriginalQueryBudget()
        var execution = try execution(budget, valueDepth: 16)
        let actual = try resolver.evaluate(expression, parameters: parameters,
            variables: variables, using: &execution)
        #expect(actual.kind == .length)
        #expect(abs(actual.value - 3) < 1e-12)
        #expect(try resolver.evaluate(expression, parameters: parameters, variables: variables) == actual)
        #expect(budget.snapshot.work > 13)
    }

    @Test
    func originalUnitDomainAndReferenceFailuresRemainTypedAndOrdered() throws {
        let resolver: any ParameterResolving = ParameterResolver()
        let table = ResolvedParameterTable()
        func evaluate(_ expression: CADExpression) throws -> Quantity {
            var execution = try execution(OriginalQueryBudget(), valueDepth: 8)
            return try resolver.evaluate(expression, parameters: table, variables: [:], using: &execution)
        }
        #expect(throws: UnitError.self) {
            _ = try evaluate(.add(.constant(.length(1, unit: .meter)), .constant(.scalar(1))))
        }
        #expect(throws: UnitError.self) {
            _ = try evaluate(.divide(.constant(.scalar(1)), .constant(.scalar(0))))
        }
        #expect(throws: UnitError.self) {
            _ = try evaluate(.sin(.constant(.length(1, unit: .meter))))
        }
        #expect(throws: UnitError.self) { _ = try evaluate(.constant(.scalar(.infinity))) }
        #expect(throws: ParameterError.self) { _ = try evaluate(.variable("invalid name", .scalar)) }
        #expect(throws: ParameterError.self) { _ = try evaluate(.variable("missing", .scalar)) }
        let firstMissing = ParameterID()
        do {
            _ = try evaluate(.add(.reference(firstMissing), .constant(.scalar(.infinity))))
            Issue.record("The first missing reference was ignored.")
        } catch let error as ParameterError {
            guard case .unknownReference(let id) = error else {
                Issue.record("The original left-before-right reference error changed.")
                return
            }
            #expect(id == firstMissing)
        }
    }

    @Test
    func allBezierExpressionProducersRetainTheOriginalContinuationLaws() throws {
        let resolver: any ParameterResolving = ParameterResolver()
        for (expression, expected) in bezierCases() {
            let budget = try OriginalQueryBudget()
            var execution = try execution(budget, valueDepth: 1)
            let value = try resolver.evaluate(expression, parameters: .init(), variables: [:], using: &execution)
            #expect(value.kind == .length)
            #expect(abs(value.value - expected) < 1e-9)
            #expect(try resolver.evaluate(expression, parameters: .init(), variables: [:]) == value)
            #expect(budget.snapshot.work > 1)
            #expect(budget.snapshot.storageBytes > 0)
        }
    }

    @Test
    func actualBezierWorkAndStorageHaveExactCumulativeBoundaries() throws {
        for (expression, _) in bezierCases() {
            let measured = try OriginalQueryBudget()
            _ = try evaluate(expression, budget: measured)
            let work = measured.snapshot.work, bytes = measured.snapshot.storageBytes
            let exact = try OriginalQueryBudget(workLimit: work, storageByteLimit: bytes)
            _ = try evaluate(expression, budget: exact)
            #expect(exact.snapshot.work == work && exact.snapshot.storageBytes == bytes)
            for (budget, resource) in [
                (try OriginalQueryBudget(workLimit: work - 1), ExactResource.work),
                (try OriginalQueryBudget(storageByteLimit: bytes - 1), ExactResource.storage),
            ] {
                do {
                    _ = try evaluate(expression, budget: budget)
                    Issue.record("A Bezier expression escaped its original cumulative ceiling.")
                } catch { expectResource(error, resource: resource) }
            }
        }
    }

    @Test
    func expressionValueDepthIsIndependentOfSourceGeometryAndCoefficientDepth() throws {
        let expression = CADExpression.add(.constant(.scalar(1)),
            .add(.constant(.scalar(2)), .constant(.scalar(3))))
        let budget = try OriginalQueryBudget()
        var exact = try execution(budget, valueDepth: 2)
        #expect(try ParameterResolver().evaluate(expression, parameters: .init(), using: &exact) == .scalar(6))
        #expect(exact.valueDepth == 2)
        #expect(exact.coefficientDepth == 0)
        var limited = try execution(OriginalQueryBudget(), valueDepth: 1)
        do {
            _ = try ParameterResolver().evaluate(expression, parameters: .init(), using: &limited)
            Issue.record("An expression exceeded its value-tree depth.")
        } catch { expectResource(error, resource: .valueDepth) }
    }

    @Test
    func repeatedQueriesAndCancellationKeepTheSameCallerBudgetBeforeOutput() throws {
        let expression = CADExpression.add(.constant(.scalar(1)), .constant(.scalar(2)))
        let measured = try OriginalQueryBudget()
        _ = try evaluate(expression, budget: measured)
        let exact = try OriginalQueryBudget(workLimit: measured.snapshot.work)
        var execution = try execution(exact, valueDepth: 8)
        #expect(try ParameterResolver().evaluate(expression, parameters: .init(), using: &execution) == .scalar(3))
        do {
            _ = try ParameterResolver().evaluate(expression, parameters: .init(), using: &execution)
            Issue.record("The second expression reset the composing caller's budget.")
        } catch { expectResource(error, resource: .work) }
        let alreadyCancelled = try OriginalQueryBudget(checkpoint: { throw CancellationError() })
        do {
            _ = try evaluate(expression, budget: alreadyCancelled)
            Issue.record("An already cancelled expression returned a quantity.")
        } catch { #expect(isCancellation(error)) }
        #expect(alreadyCancelled.snapshot.work == 0)
        for (bezier, _) in bezierCases() {
            let measured = try OriginalQueryBudget()
            _ = try evaluate(bezier, budget: measured)
            let threshold = measured.snapshot.work / 2
            // This lies after every expression child for these small coordinate
            // arrays, inside the actual continuation producer's numerical work.
            #expect(threshold > 10)
            let visits = Mutex(0)
            let cancelled = try OriginalQueryBudget(consumeWorkUnits: { units in
                let shouldCancel = visits.withLock { value in value += units; return value >= threshold }
                if shouldCancel { throw CancellationError() }
            })
            do {
                _ = try evaluate(bezier, budget: cancelled)
                Issue.record("A cancelled continuation producer returned a coordinate.")
            } catch { #expect(isCancellation(error)) }
            #expect(cancelled.snapshot.work >= threshold)
            #expect(cancelled.snapshot.work <= measured.snapshot.work)
        }
    }

    @Test
    func terminalCheckpointFollowsActualQuantityValidationBeforePublication() throws {
        let visits = Mutex(0)
        let measured = try OriginalQueryBudget(checkpoint: {
            visits.withLock { $0 += 1 }
        })
        #expect(try evaluate(.constant(.scalar(1)), budget: measured) == .scalar(1))
        let terminal = visits.withLock { $0 }
        #expect(terminal > 1)
        for invalidQuantity in [false, true] {
            let observed = Mutex(0)
            let cancelled = try OriginalQueryBudget(checkpoint: {
                let shouldCancel = observed.withLock { value in
                    value += 1
                    return value == terminal
                }
                if shouldCancel { throw CancellationError() }
            })
            do {
                _ = try evaluate(.constant(.scalar(invalidQuantity ? .infinity : 1)), budget: cancelled)
                Issue.record("A refused public expression returned a quantity.")
            } catch {
                if invalidQuantity {
                    // This authentic finite-value error occurs after node work,
                    // before the terminal checkpoint; it must win that order.
                    #expect(error is UnitError)
                    #expect(observed.withLock { $0 } == terminal - 1)
                } else {
                    #expect(isCancellation(error))
                    #expect(observed.withLock { $0 } == terminal)
                }
            }
        }
    }

    private func bezierCases() -> [(CADExpression, Double)] {
        func lengths(_ values: [Double]) -> [CADExpression] {
            values.map { .constant(.length($0, unit: .meter)) }
        }
        let length = CADExpression.constant(.length(0.5, unit: .meter))
        let line = lengths([0, 0, 1, 0])
        let cubic = lengths([0, 0, 1, 0, 2, 0, 3, 0])
        return [
            (.bezierNaturalExtension(coordinates: line, length: length, coordinateIndex: 0), 1.5),
            (.bezierShapedExtension(shape: .arc(spanCount: 1), coordinates: cubic,
                length: length, coordinateIndex: 0), 3 + 0.5 / 3),
            (.bezierShapedExtension(shape: .soft(spanCount: 1), coordinates: cubic,
                length: length, coordinateIndex: 0), 3 + 0.5 / 3),
            (.bezierShapedExtension(shape: .reflective(degree: 1, coversCurve: true),
                coordinates: line, length: length, coordinateIndex: 0), 1.5),
        ]
    }

    private func execution(_ budget: OriginalQueryBudget, valueDepth: Int) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: valueDepth,
            maximumCoefficientDepth: 0, remainingSourceDepth: 0, maximumTransportDepth: 0,
            maximumSubdivisionDepth: 0))
    }

    private func evaluate(_ expression: CADExpression, budget: OriginalQueryBudget) throws -> Quantity {
        var execution = try execution(budget, valueDepth: 16)
        let resolver: any ParameterResolving = ParameterResolver()
        return try resolver.evaluate(expression, parameters: .init(), variables: [:], using: &execution)
    }

    private func expectResource(_ error: any Error, resource: ExactResource) {
        if let failure = error as? ExactScalarFailure {
            switch failure {
            case .resourceLimit(let actual): #expect(actual == resource)
            case .admissionRejected(let cause): expectResource(cause, resource: resource)
            default: Issue.record("The original resource cause was lost: \(failure).")
            }
        } else if let failure = error as? OriginalQueryFailure {
            #expect(failure.kernelFailure.code == .resourceLimitExceeded)
            expectResource(failure.originalError, resource: resource)
        } else { Issue.record("The expression returned an unrelated failure: \(error).") }
    }

    private func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let failure = error as? ExactScalarFailure {
            switch failure {
            case .cancelled: return true
            case .admissionRejected(let cause): return isCancellation(cause)
            default: return false
            }
        }
        if let failure = error as? OriginalQueryFailure { return isCancellation(failure.originalError) }
        return false
    }
}
