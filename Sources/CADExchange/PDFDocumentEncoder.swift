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

        return try encodeContent(content, pageWidth: 612, pageHeight: 792)
    }

    func encodeDrawing(paths: [BRepDrawingOutputPath], regions: [BRepDrawingOutputRegion] = [], glyphs: [DrawingGlyphOutline] = [], pageWidth: Double, pageHeight: Double, styles: DrawingExchangeStyles, maximumBytes: Int, maximumGlyphDeviation: Double = 0, resources: inout SharedExchangeResourceAccountant) throws -> Data {
        guard pageWidth.isFinite, pageHeight.isFinite, pageWidth > 0, pageHeight > 0 else { throw ExportError.invalidMesh("Invalid PDF drawing page size.") }
        var content = "q\n"
        for region in regions {
            try Task.checkCancellation()
            content += try drawingSource(identity: region.identity, layer: "SectionMaterial",
                start: nil, end: nil, maximumBytes: maximumBytes - content.utf8.count)
            content += "\(pdfNumber(styles.material.red)) \(pdfNumber(styles.material.green)) \(pdfNumber(styles.material.blue)) rg "
            for loop in region.loops {
                guard let first = loop.first else { throw ExportError.invalidMesh("Empty PDF material loop.") }
                var record = "\(pdfNumber(first.x)) \(pdfNumber(first.y)) m "
                for point in loop.dropFirst() {
                    try Task.checkCancellation()
                    let segment = "\(pdfNumber(point.x)) \(pdfNumber(point.y)) l "
                    guard segment.utf8.count <= maximumBytes - content.utf8.count - record.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "material content exceeds byte ceiling") }
                    record += segment
                }
                record += "h "
                guard record.utf8.count <= maximumBytes - content.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "material content exceeds byte ceiling") }
                content += record
            }
            content += "f*\nEMC\n"
        }
        for path in paths {
            try Task.checkCancellation()
            let provenance = try drawingSource(identity: path.identity, layer: path.layer,
                start: path.startParameter, end: path.endParameter, originalDescriptor: path.originalRootSpanDescriptor, silhouetteDescriptor: path.originalSilhouetteDescriptor, annotationDescriptor: path.originalAnnotationDescriptor, maximumBytes: maximumBytes - content.utf8.count)
            content += provenance
            if let stations = path.nativeStations {
                var record = "/Span << /CADOriginalNativeStations ["
                for station in stations { try resources.recordIterations(); record += "\(pdfNumber(station)) " }
                record += "] >> BDC\n"
                guard record.utf8.count <= maximumBytes - content.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "native station provenance exceeds byte ceiling") }
                content += record
            }
            let style = styles.stroke(for: path.layer)
            content += "q \(pdfNumber(style.red)) \(pdfNumber(style.green)) \(pdfNumber(style.blue)) RG \(pdfNumber(style.red)) \(pdfNumber(style.green)) \(pdfNumber(style.blue)) rg \(pdfNumber(style.width)) w ["
            for length in style.dashPattern {
                let token = "\(pdfNumber(length)) "
                guard token.utf8.count <= maximumBytes - content.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "physical dash pattern exceeds byte ceiling") }
                content += token
            }
            content += "] 0 d\n"
            guard let first = path.points.first else { throw ExportError.invalidMesh("Invalid PDF drawing path.") }
            if path.points.count == 1 {
                let record = "\(pdfNumber(first.x - style.width / 2)) \(pdfNumber(first.y - style.width / 2)) \(pdfNumber(style.width)) \(pdfNumber(style.width)) re f\n"
                guard record.utf8.count <= maximumBytes - content.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "drawing point exceeds byte ceiling") }
                content += record + "Q\nEMC\n"
                if path.nativeStations != nil { content += "EMC\n" }
                continue
            }
            content += "\(pdfNumber(first.x)) \(pdfNumber(first.y)) m "
            for point in path.points.dropFirst() {
                try Task.checkCancellation()
                let record = "\(pdfNumber(point.x)) \(pdfNumber(point.y)) l "
                guard record.utf8.count <= maximumBytes - content.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "drawing content exceeds byte ceiling") }
                content += record
            }
            content += "S\nQ\nEMC\n"
            if path.nativeStations != nil { content += "EMC\n" }
        }
        for glyph in glyphs {
            try resources.checkTime()
            try resources.recordIterations(glyph.text.utf8.count + glyph.fontPostScriptName.utf8.count)
            for value in [glyph.text, glyph.fontPostScriptName] {
                let size = value.utf16.count.multipliedReportingOverflow(by: 4)
                guard !size.overflow else { throw exchangeResourceLimitError(format: .pdf, detail: "original glyph text encoding overflows") }
                try resources.recordBytes(size.partialValue)
            }
            var record = try drawingSource(identity: glyph.identity, layer: "Annotation", start: nil, end: nil,
                maximumBytes: maximumBytes - content.utf8.count)
            record += "/Span << /CADOriginalText \(textString(glyph.text)) /CADPostScriptFont \(textString(glyph.fontPostScriptName)) /CADFontSizePaperPoints \(pdfNumber(glyph.fontSize)) >> BDC\n"
            let color = styles.annotation
            record += "q \(pdfNumber(color.red)) \(pdfNumber(color.green)) \(pdfNumber(color.blue)) rg\n"
            var current = Point2D(x: 0, y: 0), first = current
            for command in glyph.commands {
                try resources.recordIterations(); try resources.checkTime()
                let token: String
                switch command {
                case .move(let point): current = point; first = point; token = "\(pdfNumber(point.x)) \(pdfNumber(point.y)) m "
                case .line(let point): current = point; token = "\(pdfNumber(point.x)) \(pdfNumber(point.y)) l "
                case .quadratic(let control, let end):
                    var originalUsage = DrawingExchangeUsage(resources: resources)
                    let controls = try DrawingGlyphQuadraticConversion.controls(start: current, control: control, end: end,
                        allowance: maximumGlyphDeviation, usage: &originalUsage)
                    resources = originalUsage.resources; current = end
                    token = "\(pdfNumber(controls.0.x)) \(pdfNumber(controls.0.y)) \(pdfNumber(controls.1.x)) \(pdfNumber(controls.1.y)) \(pdfNumber(end.x)) \(pdfNumber(end.y)) c "
                    // Original quadratic controls are preserved separately from admitted target controls.
                    record += "% OriginalQuadratic \(pdfNumber(control.x)) \(pdfNumber(control.y)) \(pdfNumber(end.x)) \(pdfNumber(end.y))\n"
                case .cubic(let a, let b, let end): current = end; token = "\(pdfNumber(a.x)) \(pdfNumber(a.y)) \(pdfNumber(b.x)) \(pdfNumber(b.y)) \(pdfNumber(end.x)) \(pdfNumber(end.y)) c "
                case .close: current = first; token = "h "
                }
                guard token.utf8.count <= maximumBytes - content.utf8.count - record.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "original glyph path exceeds byte ceiling") }
                record += token
            }
            record += glyph.commands.isEmpty ? "Q\nEMC\nEMC\n" : (glyph.fillRule == .evenOdd ? "f*\nQ\nEMC\nEMC\n" : "f\nQ\nEMC\nEMC\n")
            guard record.utf8.count <= maximumBytes - content.utf8.count else { throw exchangeResourceLimitError(format: .pdf, detail: "glyph content exceeds byte ceiling") }
            content += record
        }

        content += "Q\n"
        return try encodeContent(content, pageWidth: pageWidth, pageHeight: pageHeight)
    }

    private func drawingSource(identity: String, layer: String, start: Double?, end: Double?, originalDescriptor: String? = nil, silhouetteDescriptor: String? = nil, annotationDescriptor: String? = nil, maximumBytes: Int) throws -> String {
        func encodedSize(_ value: String) throws -> Int {
            var ascii = true, bytes = 2
            for scalar in value.unicodeScalars {
                try Task.checkCancellation()
                if scalar.value > 0x7f { ascii = false; break }
                let count: Int
                switch scalar.value {
                case 0x08, 0x09, 0x0a, 0x0c, 0x0d, 0x28, 0x29, 0x5c: count = 2
                case 0x00...0x1f, 0x7f: count = 4
                default: count = 1
                }
                guard count <= maximumBytes - bytes else { throw exchangeResourceLimitError(format: .pdf, detail: "drawing identity exceeds byte ceiling") }
                bytes += count
            }
            if ascii { return bytes }
            let size = value.utf16.count.multipliedReportingOverflow(by: 4)
            guard !size.overflow, size.partialValue <= maximumBytes - 6 else { throw exchangeResourceLimitError(format: .pdf, detail: "drawing identity exceeds byte ceiling") }
            return size.partialValue + 6
        }
        let identitySize = try encodedSize(identity), layerSize = try encodedSize(layer)
        var descriptorSize = 0
        for descriptor in [originalDescriptor, silhouetteDescriptor, annotationDescriptor] {
            if let descriptor {
                let size = try encodedSize(descriptor)
                guard size <= maximumBytes - descriptorSize else { throw exchangeResourceLimitError(format: .pdf, detail: "drawing provenance exceeds byte ceiling") }
                descriptorSize += size
            }
        }
        guard identitySize <= maximumBytes - layerSize - descriptorSize else { throw exchangeResourceLimitError(format: .pdf, detail: "drawing provenance exceeds byte ceiling") }
        guard (start == nil) == (end == nil) else { throw ExportError.invalidMesh("PDF original drawing interval is incomplete.") }
        var record = "/Span << /CADSourceIdentity \(textString(identity)) /CADSourceLayer \(textString(layer))"
        if let start, let end {
            guard start.isFinite, end.isFinite else { throw ExportError.invalidMesh("PDF original drawing interval is nonfinite.") }
            record += " /CADNativeStart \(pdfNumber(start)) /CADNativeEnd \(pdfNumber(end))"
        }
        if let originalDescriptor { record += " /CADOriginalAlgebraicSpanJSON \(textString(originalDescriptor))" }
        if let silhouetteDescriptor { record += " /CADOriginalSilhouetteJSON \(textString(silhouetteDescriptor))" }
        if let annotationDescriptor { record += " /CADOriginalAnnotationJSON \(textString(annotationDescriptor))" }
        record += " >> BDC\n"
        guard record.utf8.count <= maximumBytes else { throw exchangeResourceLimitError(format: .pdf, detail: "drawing provenance exceeds byte ceiling") }
        return record
    }

    private func encodeContent(_ content: String, pageWidth: Double, pageHeight: Double) throws -> Data {
        let objects = [
            "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n",
            "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n",
            "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 \(number(pageWidth)) \(number(pageHeight))] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n",
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

    /// PDF real tokens use decimal notation; exponent notation is not a PDF number.
    private func pdfNumber(_ value: Double) -> String {
        let original = stepNumber(value)
        guard let exponentStart = original.firstIndex(where: { $0 == "e" || $0 == "E" }),
              let exponent = Int(original[original.index(after: exponentStart)...]) else { return original }
        var mantissa = String(original[..<exponentStart])
        let negative = mantissa.first == "-"
        if negative { mantissa.removeFirst() }
        let components = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let integerCount = components[0].count
        let digits = components.joined()
        let position = integerCount + exponent
        let decimal: String
        if position <= 0 { decimal = "0." + String(repeating: "0", count: -position) + digits }
        else if position >= digits.count { decimal = digits + String(repeating: "0", count: position - digits.count) }
        else {
            let index = digits.index(digits.startIndex, offsetBy: position)
            decimal = String(digits[..<index]) + "." + digits[index...]
        }
        return negative ? "-" + decimal : decimal
    }

    private func number(_ value: Double) -> String {
        pdfNumber(value)
    }
}
