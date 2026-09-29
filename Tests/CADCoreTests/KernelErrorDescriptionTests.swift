import Foundation
import Testing
@testable import CADCore

/// A kernel error shows its message, and keeps its phase and code for debugging.
@Test func aKernelErrorReadsAsItsMessage() {
    let error = KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: .standard,
        message: "Fillet radius must fit both endpoint edges.")
    #expect("\(error)" == "Fillet radius must fit both endpoint edges.")
    #expect(error.localizedDescription == "Fillet radius must fit both endpoint edges.")
    #expect(String(reflecting: error).contains("unsupportedCapability"))
    #expect(String(reflecting: error).contains("evaluation"))
}
