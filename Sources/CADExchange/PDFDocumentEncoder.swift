import Foundation
import CADCore

struct PDFDocumentEncoder: Sendable {
    func encode(lines: [String], projection: PDFMeshProjection) throws -> Data {
        var content = "% Swift-CAD projection \(projection.plane.rawValue)\n"
        content += "q 0.35 w 0 G\n"
        for triangle in projection.triangles {
            guard triangle.count == 3 else {
                throw ExportError.invalidMesh("PDF projection produced an invalid triangle path.")
            }
            content += "\(number(triangle[0].x)) \(number(triangle[0].y)) m "
            content += "\(number(triangle[1].x)) \(number(triangle[1].y)) l "
            content += "\(number(triangle[2].x)) \(number(triangle[2].y)) l h S\n"
        }
        content += "Q\n"
        for (index, line) in lines.enumerated() {
            content += "BT /F1 14 Tf 1 0 0 1 48 \(744 - index * 20) Tm \(textString(line)) Tj ET\n"
        }

        let objects = [
            "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n",
            "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n",
            "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n",
            "4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n",
            "5 0 obj << /Length \(content.utf8.count) >> stream\n\(content)endstream\nendobj\n",
        ]
        var result = "%PDF-1.4\n"
        var offsets: [Int] = []
        offsets.reserveCapacity(objects.count)
        for object in objects {
            offsets.append(result.utf8.count)
            result += object
        }
        let xrefOffset = result.utf8.count
        result += "xref\n0 \(objects.count + 1)\n"
        result += "0000000000 65535 f \n"
        for offset in offsets {
            result += String(format: "%010d 00000 n \n", locale: Locale(identifier: "en_US_POSIX"), offset)
        }
        result += "trailer << /Size \(objects.count + 1) /Root 1 0 R >>\n"
        result += "startxref\n\(xrefOffset)\n%%EOF\n"
        return Data(result.utf8)
    }

    private func textString(_ text: String) -> String {
        guard text.unicodeScalars.allSatisfy({ $0.value <= 0x7f }) else {
            var bytes: [UInt8] = [0xfe, 0xff]
            bytes.reserveCapacity(2 + text.utf16.count * 2)
            for codeUnit in text.utf16 {
                bytes.append(UInt8(codeUnit >> 8))
                bytes.append(UInt8(codeUnit & 0xff))
            }
            return "<\(bytes.map { String(format: "%02X", $0) }.joined())>"
        }

        var result = "("
        result.reserveCapacity(text.count + 2)
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
        result += ")"
        return result
    }

    private func number(_ value: Double) -> String {
        String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
