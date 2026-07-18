import Foundation
import CADCore
import CADIR

public struct PDFExporter: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func write(meshes: [BodyID: Mesh], title: String = "Swift-CAD Export", to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let triangleCount = try meshes.values.reduce(0) { partial, mesh in
            try mesh.validate(tolerance: tolerance)
            return partial + mesh.indices.count / 3
        }
        let vertexCount = meshes.values.reduce(0) { $0 + $1.positions.count }
        let bodyCount = meshes.count
        let lines = [
            title,
            "Official Swift-CAD document output",
            "Bodies: \(bodyCount)",
            "Vertices: \(vertexCount)",
            "Triangles: \(triangleCount)"
        ]
        try sink.writeUTF8(pdf(lines: lines))
    }

    private func pdf(lines: [String]) -> String {
        let content = lines.enumerated().map { index, line in
            "BT /F1 14 Tf 72 \(740 - index * 24) Td (\(escape(line))) Tj ET"
        }.joined(separator: "\n")
        let stream = "\(content)\n"
        let objects = [
            "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n",
            "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n",
            "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n",
            "4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n",
            "5 0 obj << /Length \(stream.utf8.count) >> stream\n\(stream)endstream endobj\n"
        ]
        var result = "%PDF-1.4\n"
        var offsets: [Int] = [0]
        for object in objects {
            offsets.append(result.utf8.count)
            result += object
        }
        let xrefOffset = result.utf8.count
        result += "xref\n0 \(objects.count + 1)\n"
        result += "0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            result += String(format: "%010d 00000 n \n", offset)
        }
        result += "trailer << /Size \(objects.count + 1) /Root 1 0 R >>\n"
        result += "startxref\n\(xrefOffset)\n%%EOF\n"
        return result
    }

    private func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x08:
                result += "\\b"
            case 0x09:
                result += "\\t"
            case 0x0a:
                result += "\\n"
            case 0x0c:
                result += "\\f"
            case 0x0d:
                result += "\\r"
            case 0x28:
                result += "\\("
            case 0x29:
                result += "\\)"
            case 0x5c:
                result += "\\\\"
            case 0x00...0x1f, 0x7f:
                result += String(format: "\\%03o", Int(scalar.value))
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
