import Foundation
import CADCore
import CADGeometry

extension BRepDrawingExchange {
    func validateGlyph(_ glyph: DrawingGlyphOutline, resources: SharedExchangeResourceAccountant) throws {
        try resources.recordIterations(glyph.text.utf8.count + glyph.fontPostScriptName.utf8.count + glyph.identity.utf8.count)
        guard !glyph.identity.isEmpty, !glyph.fontPostScriptName.isEmpty,
              glyph.fontSize.isFinite, glyph.fontSize > 0 else { throw ExportError.invalidMesh("Glyph run lacks original font, size or source identity.") }
        if glyph.commands.isEmpty {
            guard glyph.text.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else {
                throw ExportError.invalidMesh("A non-whitespace shaped run has no actual glyph outline.")
            }
            return
        }
        var active = false, edges = 0
        func point(_ value: Point2D) throws {
            guard value.x.isFinite, value.y.isFinite else { throw ExportError.invalidMesh("Glyph outline point is nonfinite.") }
        }
        for command in glyph.commands {
            try resources.recordIterations(); try resources.checkTime()
            switch command {
            case .move(let value):
                guard !active else { throw ExportError.invalidMesh("Glyph contour is not explicitly closed.") }
                try point(value); active = true; edges = 0
            case .line(let value):
                guard active else { throw ExportError.invalidMesh("Glyph edge lacks its original contour start.") }
                try point(value); edges += 1
            case .quadratic(let control, let end):
                guard active else { throw ExportError.invalidMesh("Glyph quadratic lacks its original start.") }
                try point(control); try point(end); edges += 1
            case .cubic(let first, let second, let end):
                guard active else { throw ExportError.invalidMesh("Glyph cubic lacks its original start.") }
                try point(first); try point(second); try point(end); edges += 1
            case .close:
                guard active, edges > 0 else { throw ExportError.invalidMesh("Glyph contour is empty or has no start.") }
                active = false
            }
        }
        guard !active else { throw ExportError.invalidMesh("Final glyph contour is not closed.") }
    }

    func writeSVGGlyph(_ glyph: DrawingGlyphOutline, options: DrawingExchangeOptions, to sink: any ByteSink,
                       resources: SharedExchangeResourceAccountant) throws {
        let identity = try xmlAttribute(glyph.identity, resources: resources)
        let text = try xmlAttribute(glyph.text, resources: resources)
        let font = try xmlAttribute(glyph.fontPostScriptName, resources: resources)
        let color = options.styles.annotation
        let rule = glyph.fillRule == .evenOdd ? "evenodd" : "nonzero"
        try sink.writeUTF8("<path data-source-id=\"\(identity)\" data-original-text=\"\(text)\" data-font-postscript=\"\(font)\" data-font-size-pt=\"\(stepNumber(glyph.fontSize))\" fill=\"\(svgColor(color.red, color.green, color.blue))\" fill-rule=\"\(rule)\" d=\"")
        for command in glyph.commands {
            try resources.recordIterations(); try resources.checkTime()
            func token(_ point: Point2D) throws -> String {
                let value = try paperPoint(point, outputUnit: options.outputUnit)
                return "\(stepNumber(value.x)) \(stepNumber(value.y))"
            }
            switch command {
            case .move(let point): try sink.writeUTF8("M \(try token(point)) ")
            case .line(let point): try sink.writeUTF8("L \(try token(point)) ")
            case .quadratic(let control, let end): try sink.writeUTF8("Q \(try token(control)) \(try token(end)) ")
            case .cubic(let first, let second, let end): try sink.writeUTF8("C \(try token(first)) \(try token(second)) \(try token(end)) ")
            case .close: try sink.writeUTF8("Z ")
            }
        }
        try sink.writeUTF8("\"/>\n")
    }

    func writeDXFGlyph(_ glyph: DrawingGlyphOutline, resolved: DrawingResolvedGlyphBoundary? = nil,
                       maximumDeviation: Double? = nil, options: DrawingExchangeOptions, to sink: any ByteSink,
                       resources: SharedExchangeResourceAccountant, using execution: inout OriginalQueryExecution) throws {
        if glyph.fillRule == .nonzero, !glyph.commands.isEmpty {
            guard let resolved, let maximumDeviation, try resolved.matches(glyph, resources: resources) else {
                throw ExportError.invalidMesh("DXF nonzero glyph requires a matching original true boundary receipt and caller deviation.")
            }
            try writeDXFResolvedGlyph(resolved, maximumDeviation: maximumDeviation,
                options: options, to: sink, resources: resources, using: &execution)
            return
        }
        let color = options.styles.annotation
        let contours = glyph.commands.reduce(0) { value, command in if case .move = command { value + 1 } else { value } }
        try resources.recordIterations(glyph.commands.count)
        if !glyph.commands.isEmpty {
            try sink.writeUTF8("0\nHATCH\n100\nAcDbEntity\n8\nAnnotation\n420\n\(color.trueColor)\n100\nAcDbHatch\n10\n0\n20\n0\n30\n0\n210\n0\n220\n0\n230\n1\n2\nSOLID\n70\n1\n71\n0\n91\n\(contours)\n")
            var ordinal = 0
            while ordinal < glyph.commands.count {
                guard case .move(let originalStart) = glyph.commands[ordinal] else { throw ExportError.invalidMesh("Invalid original glyph contour partition.") }
                var close = ordinal + 1
                while close < glyph.commands.count {
                    try resources.recordIterations()
                    if case .close = glyph.commands[close] { break }
                    close += 1
                }
                guard close < glyph.commands.count else { throw ExportError.invalidMesh("Unclosed original glyph contour.") }
                var current = originalStart
                let closingEdges: Int
                if close > ordinal + 1 {
                    switch glyph.commands[close - 1] {
                    case .line(let end), .quadratic(_, let end), .cubic(_, _, let end): closingEdges = end == originalStart ? 0 : 1
                    default: throw ExportError.invalidMesh("Invalid glyph contour final edge.")
                    }
                } else { throw ExportError.invalidMesh("Empty glyph contour.") }
                try sink.writeUTF8("92\n0\n93\n\(close - ordinal - 1 + closingEdges)\n")
                func line(_ first: Point2D, _ last: Point2D) throws {
                    let a = try paperPoint(first, outputUnit: options.outputUnit), b = try paperPoint(last, outputUnit: options.outputUnit)
                    try sink.writeUTF8("72\n1\n10\n\(stepNumber(a.x))\n20\n\(stepNumber(a.y))\n11\n\(stepNumber(b.x))\n21\n\(stepNumber(b.y))\n")
                }
                for index in (ordinal + 1)..<close {
                    try resources.recordIterations()
                    let controls: [Point2D]
                    switch glyph.commands[index] {
                    case .line(let end): try line(current, end); current = end; continue
                    case .quadratic(let control, let end): controls = [current, control, end]; current = end
                    case .cubic(let first, let second, let end): controls = [current, first, second, end]; current = end
                    default: throw ExportError.invalidMesh("Invalid original glyph edge.")
                    }
                    try resources.recordBytes(controls.count * MemoryLayout<Point2D>.stride)
                    let degree = controls.count - 1
                    try sink.writeUTF8("72\n4\n94\n\(degree)\n73\n0\n74\n0\n95\n\(2 * controls.count)\n96\n\(controls.count)\n")
                    for _ in controls { try sink.writeUTF8("40\n0\n") }
                    for _ in controls { try sink.writeUTF8("40\n1\n") }
                    for point in controls {
                        let value = try paperPoint(point, outputUnit: options.outputUnit)
                        try sink.writeUTF8("10\n\(stepNumber(value.x))\n20\n\(stepNumber(value.y))\n")
                    }
                    try sink.writeUTF8("97\n0\n")
                }
                if closingEdges == 1 { try line(current, originalStart) }
                try sink.writeUTF8("97\n0\n")
                ordinal = close + 1
            }
            try sink.writeUTF8("75\n0\n76\n1\n98\n0\n")
        } else {
            // A whitespace run is a nongeometric source record, not a fabricated visible glyph.
            try sink.writeUTF8("0\nTEXT\n100\nAcDbEntity\n8\nAnnotation\n100\nAcDbText\n10\n0\n20\n0\n40\n\(stepNumber(try options.outputLength(paperPoints: glyph.fontSize)))\n1\n \n")
        }
        try writeDXFGlyphProvenance(glyph, to: sink, resources: resources)
    }

    func writeDXFGlyphProvenance(_ glyph: DrawingGlyphOutline, to sink: any ByteSink,
                                 resources: SharedExchangeResourceAccountant) throws {
        try sink.writeUTF8("1001\nSWIFTCAD\n")
        try writeDXFIdentity(glyph.identity, to: sink, resources: resources)
        try sink.writeUTF8("1000\noriginalGlyphText\n")
        try writeDXFIdentity(glyph.text, to: sink, resources: resources)
        try sink.writeUTF8("1000\noriginalGlyphPostScriptFont\n")
        try writeDXFIdentity(glyph.fontPostScriptName, to: sink, resources: resources)
        try sink.writeUTF8("1000\noriginalGlyphSizePaperPoints\n1040\n\(stepNumber(glyph.fontSize))\n1000\noriginalGlyphFillRule\n1000\n\(glyph.fillRule == .nonzero ? "nonzero" : "evenOdd")\n")
        for command in glyph.commands {
            try resources.recordIterations()
            let kind: String, points: [Point2D]
            switch command {
            case .move(let point): kind = "move"; points = [point]
            case .line(let point): kind = "line"; points = [point]
            case .quadratic(let control, let end): kind = "quadratic"; points = [control, end]
            case .cubic(let first, let second, let end): kind = "cubic"; points = [first, second, end]
            case .close: kind = "close"; points = []
            }
            try sink.writeUTF8("1000\n\(kind)\n")
            for point in points { try sink.writeUTF8("1040\n\(stepNumber(point.x))\n1040\n\(stepNumber(point.y))\n") }
        }
    }
}
