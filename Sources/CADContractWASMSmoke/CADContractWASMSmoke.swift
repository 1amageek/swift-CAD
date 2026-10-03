import CADCore
import CADCapabilities
import Foundation

@main
struct CADContractWASMSmoke {
    static func main() throws {
        let catalog = KernelCapabilities.current
        try catalog.validate()
        for capability in catalog.capabilities {
            let domain = try catalog.domain(operation: capability.operation)
            let transported = try JSONDecoder().decode(
                KernelCapabilityDomain.self, from: JSONEncoder().encode(domain)
            )
            guard transported == domain, domain.capability == capability else {
                throw failure("A public domain changed during transport.")
            }
        }
        for (operation, dimension) in [
            ("faceAreaMeasurement", KernelDomainDimension.supportSurface),
            ("edgeOffset", .boundaryCurve), ("fillet", .connection), ("untrimFace", .degeneracy),
        ] {
            guard !(try catalog.domain(operation: operation)).limitations(affecting: dimension).isEmpty else {
                throw failure("A public domain lost its source-owned dimension.")
            }
        }
        do {
            _ = try catalog.domain(operation: "unknownOperation")
            throw failure("An unknown operation produced a provisional domain.")
        } catch let error as KernelError {
            guard error.code == .unsupportedCapability else { throw error }
        }
        let resource = KernelError.wrapping(
            TessellationError.resourceExhausted(.triangleCount, requested: 12, limit: 10),
            phase: .evaluation, tolerance: .standard
        )
        guard resource.code == .resourceLimitExceeded, resource.category == .resourceExhaustion else {
            throw failure("Failure wrapping lost a resource cause.")
        }
        print("CADContractWASMSmoke passed: public domains, transport, dimensional filters, unknown-operation refusal and failure causes")
    }

    private static func failure(_ message: String) -> KernelError {
        KernelError(phase: .validation, code: .invalidInput, tolerance: .standard, message: message)
    }
}
