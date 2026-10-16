import CADCore
import CADGeometry

package struct ExactLoftGuideCurve: Sendable {
    package let originalChain: OriginalLoftGuideChain
    package let sectionContacts: [OriginalLoftGuideContact]
    package let boundaryLoopIndex: Int
    package let sectionPoints: [Point3D]
    package let sectionBoundaryLoopIndexes: [Int]

    /// Legacy diagnostic image; production connectors restrict the original chain directly.
    @available(*, deprecated, message: "Use originalChain and sectionContacts for original event authority.")
    package var curve: BSplineCurve3D {
        get throws {
            guard let first = sectionContacts.first, let last = sectionContacts.last else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: originalChain.tolerance,
                    message: "An original Loft guide has no section interval for a diagnostic image.")
            }
            var execution = try OriginalQueryExecution.independentGeometry()
            return try originalChain.connector(from: first, to: last, tolerance: originalChain.tolerance, using: &execution)
        }
    }

    /// Directed chain progress is diagnostic; it is not a spline/native parameter map.
    @available(*, deprecated, message: "Original section parameters are sectionContacts[].parameters.")
    package var sectionParameters: [Double] {
        get throws {
            try sectionContacts.map { try originalChain.orderedBounds($0, tolerance: originalChain.tolerance).midpoint }
        }
    }
}
