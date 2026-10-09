#if ORIGINAL_COORDINATE_ISOLATED_VERIFICATION
import L0
import L1
@testable import L2
#elseif L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// The mutable embedding table belongs exclusively to this invocation.
public struct DefaultExactOriginalScalarTransporter: ExactOriginalScalarTransferring {
    public init() {}
    public func transfer<A: ExactScalarAdmission & ~Copyable>(
        _ values: borrowing [ExactAlgebraicScalar<OriginalExactScalarDomain>],
        into destination: borrowing OriginalExactScalarDomain, using admission: inout A
    ) throws(ExactScalarFailure) -> ExactOriginalScalarTransferReceipt {
        try admission.checkpoint()
        var state = OriginalCoordinateTransportState(field: copy destination)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: values.count,
            of: OriginalExactScalar.self))
        var result: [OriginalExactScalar] = []; result.reserveCapacity(values.count)
        for index in values.indices {
            result.append(try state.value(values[index], using: &admission))
        }
        let final = try DefaultOriginalScalarTransporter().transfer(result,
            into: state.field, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
            of: ExactOriginalScalarTransferReceipt.self))
        let receipt = ExactOriginalScalarTransferReceipt(sources: copy values,
            field: final.field, values: final.values)
        try admission.checkpoint(); return receipt
    }
}
