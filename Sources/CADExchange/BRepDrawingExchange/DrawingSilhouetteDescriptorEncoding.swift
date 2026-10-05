import Foundation
import CADCore
import CADGeometry

/// Encloses a successfully completed original event stream; failures never yield a descriptor.
enum DrawingSilhouetteDescriptorEncoding {
    static func complete<Header: Encodable>(_ headerValue: Header, drawing: DrawingExchangeUsage,
        lower: inout SurfaceSilhouetteUsage, tolerance: ModelingTolerance,
        visit: (any SurfaceSilhouetteProvenanceWriting, inout SurfaceSilhouetteUsage) throws -> Void) throws -> String {
        let accounting = DrawingSilhouetteJSONAccounting(drawing: drawing, silhouette: lower)
        let header = try NativeBoundedJSONEncoder().encode(headerValue, resources: accounting)
        guard header.last == 0x7d else { throw ExportError.invalidMesh("Original silhouette header is not a complete JSON record.") }
        let sink = DrawingSilhouetteProvenanceSink(drawing: drawing, silhouetteUsage: lower, tolerance: tolerance)
        try visit(sink, &lower)
        let events = try sink.complete(usage: &lower)
        let field = ",\"events\":"
        try accounting.recordBytes(field.utf8.count + 1, label: "source framing")
        var complete = header
        complete.removeLast(); complete.append(contentsOf: field.utf8); complete.append(events); complete.append(0x7d)
        try accounting.checkTime()
        guard let result = String(data: complete, encoding: .utf8) else { throw ExportError.invalidMesh("Original silhouette descriptor is not valid UTF-8.") }
        return result
    }
}
