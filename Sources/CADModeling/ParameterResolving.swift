import CADCore
import CADIR

/// Resolves document parameters and evaluates unit-aware feature expressions.
public protocol ParameterResolving: Sendable {
    func resolve(_ table: ParameterTable) throws -> ResolvedParameterTable

    func evaluate(
        _ expression: CADExpression,
        parameters: ResolvedParameterTable,
        variables: [String: Quantity]
    ) throws -> Quantity
}
