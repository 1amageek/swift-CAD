import CADCore
import CADIR
import CADGeometry

/// Resolves document parameters and evaluates unit-aware feature expressions.
public protocol ParameterResolving: Sendable {
    func resolve(_ table: ParameterTable) throws -> ResolvedParameterTable

    func evaluate(
        _ expression: CADExpression,
        parameters: ResolvedParameterTable,
        variables: [String: Quantity]
    ) throws -> Quantity

    func evaluate(
        _ expression: CADExpression,
        parameters: ResolvedParameterTable,
        variables: [String: Quantity],
        using execution: inout OriginalQueryExecution
    ) throws -> Quantity

    func resolve(_ table: ParameterTable, using execution: inout OriginalQueryExecution) throws -> ResolvedParameterTable
}

public extension ParameterResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy external resolvers reach this
    // direct whole-table witness until they implement caller-owned validation,
    // dependency resolution and publication without resetting the execution.
    func resolve(_ table: ParameterTable, using execution: inout OriginalQueryExecution) throws -> ResolvedParameterTable {
        try execution.checkpoint()
        throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: nil,
            message: "Parameter resolver does not implement caller-execution whole-table resolution.")
    }
}
