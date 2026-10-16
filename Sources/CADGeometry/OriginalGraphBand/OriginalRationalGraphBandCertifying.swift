import CADCore

/// Original graph/reference geometry authority; the consumer separately owns spatial-edge correspondence.
package protocol OriginalRationalGraphBandCertifying: Sendable {
    func certify(input: OriginalGraphBandInput, fidelity: OriginalGraphBandInput.Fidelity,
                 tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
      throws -> OriginalGraphBandReceipt
}
