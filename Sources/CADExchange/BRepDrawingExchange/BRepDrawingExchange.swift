import Foundation
import CADCore
import CADGeometry
import CADTopology
import CADKernel

public struct BRepDrawingExchange: BRepDrawingExchanging {
    let resourceLimits: ExchangeResourceLimits
    public init(resourceLimits: ExchangeResourceLimits = .standard) { self.resourceLimits = resourceLimits }
    public func write(_ projection: BRepDrawingPlacedProjection, in evaluated: EvaluatedDocument,
                      as format: ExchangeFileFormat, options: DrawingExchangeOptions = .init(),
                      to sink: any ByteSink) throws {
        try projection.validateCurrent(evaluated)
        try options.validate()
        guard [.dxf, .svg, .pdf].contains(format) else { throw ImportError.unsupportedFormat(format.displayName) }
        let resources = try SharedExchangeResourceAccountant(limits: resourceLimits, format: format)
        var execution = try DrawingExchangeOwner(resources: resources).execution()
        try resources.recordEntities(projection.placements.count)
        try resources.recordEntities(projection.uses.count)
        try resources.recordBytes(projection.uses.count * MemoryLayout<BRepDrawingOutputPath>.stride)
        var records: [BRepDrawingOutputPath] = []
        records.reserveCapacity(projection.uses.count)
        for use in projection.uses {
            try resources.checkTime()
            let edge = use.original.edge
            let identity = "\(use.placement.identity)/\(edge.edgeID)"
            try resources.recordIterations(identity.utf8.count)
            try resources.recordBytes(identity.utf8.count)
            let points = try linearize(use.curve, from: edge.startParameter, to: edge.endParameter,
                options: options, resources: resources, using: &execution)
            records.append(.init(points: points, layer: "Geometry", identity: identity,
                startParameter: edge.startParameter, endParameter: edge.endParameter))
        }
        try publish(records, as: format, options: options, resources: resources, to: sink, using: &execution)
    }

    public func write(_ projection: BRepDrawingProjection, in evaluated: EvaluatedDocument,
                      as format: ExchangeFileFormat, options: DrawingExchangeOptions = .init(),
                      to sink: any ByteSink) throws {
        try projection.validateCurrent(evaluated)
        try write(projection, as: format, options: options, to: sink)
    }

    /// Exports the retained immutable projection without asserting current-document freshness.
    public func write(_ projection: BRepDrawingProjection, as format: ExchangeFileFormat,
                      options: DrawingExchangeOptions = .init(), to sink: any ByteSink) throws {
        try options.validate()
        guard [.dxf, .svg, .pdf].contains(format) else { throw ImportError.unsupportedFormat(format.displayName) }
        let resources = try SharedExchangeResourceAccountant(limits: resourceLimits, format: format)
        var execution = try DrawingExchangeOwner(resources: resources).execution()
        guard !projection.uses.isEmpty else { throw ExportError.invalidMesh("Drawing contains no projected source uses.") }
        try resources.recordEntities(projection.uses.count)
        try resources.recordBytes(projection.uses.count * MemoryLayout<BRepDrawingOutputPath>.stride)
        var records: [BRepDrawingOutputPath] = []
        records.reserveCapacity(projection.uses.count)
        for use in projection.uses {
            try resources.checkTime()
            let edge = use.edge
            let points = try linearize(edge.curve, from: edge.startParameter, to: edge.endParameter,
                options: options, resources: resources, using: &execution)
            records.append(BRepDrawingOutputPath(points: points, layer: "Geometry", identity: edge.edgeID.description,
                startParameter: edge.startParameter, endParameter: edge.endParameter))
        }
        try publish(records, as: format, options: options, resources: resources, to: sink, using: &execution)
    }

    func linearize(_ curve: OrthographicProjectedCurve, from start: Double, to end: Double,
                   options: DrawingExchangeOptions, resources: SharedExchangeResourceAccountant, using execution: inout OriginalQueryExecution) throws -> [Point2D] {
        let original = try DefaultBRepDrawingCurveLinearizer().linearize(curve, from: start, to: end,
            maximumDeviation: options.maximumCurveDeviation, resources: resources, using: &execution)
        try resources.recordBytes(original.samples.count * MemoryLayout<Point2D>.stride)
        var points: [Point2D] = []
        points.reserveCapacity(original.samples.count)
        for sample in original.samples {
            try resources.recordIterations()
            points.append(try options.transform(sample.point))
        }
        return points
    }

    func publish(_ paths: [BRepDrawingOutputPath], regions: [BRepDrawingOutputRegion] = [], glyphs: [DrawingGlyphOutline] = [],
                 resolvedGlyphBoundaries: [String: DrawingResolvedGlyphBoundary] = [:], maximumGlyphDeviation: Double? = nil, as format: ExchangeFileFormat,
                 options: DrawingExchangeOptions, resources: SharedExchangeResourceAccountant,
                 to sink: any ByteSink, using execution: inout OriginalQueryExecution) throws {
        for style in options.styles.strokes { try resources.recordIterations(style.dashPattern.count + 1) }
        let output = DataByteSink()
        let bounded = try ExchangeBoundedByteSink(downstream: output, limits: resources.limits, format: format)
        switch format {
        case .dxf:
            try bounded.writeUTF8("0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1027\n9\n$INSUNITS\n70\n\(unitCode(options.outputUnit))\n0\nENDSEC\n0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nAPPID\n70\n1\n0\nAPPID\n2\nSWIFTCAD\n70\n0\n0\nENDTAB\n")
            try writeDXFStyles(options, to: bounded, resources: resources)
            try bounded.writeUTF8("0\nENDSEC\n0\nSECTION\n2\nENTITIES\n")
            for region in regions {
                try resources.checkTime()
                try bounded.writeUTF8("0\nHATCH\n100\nAcDbEntity\n8\nSectionMaterial\n420\n\(options.styles.material.trueColor)\n100\nAcDbHatch\n10\n0\n20\n0\n30\n0\n210\n0\n220\n0\n230\n1\n2\nSOLID\n70\n1\n71\n0\n91\n\(region.loops.count)\n")
                for (index, loop) in region.loops.enumerated() {
                    try bounded.writeUTF8("92\n\(region.outer[index] ? 3 : 2)\n72\n0\n73\n1\n93\n\(loop.count)\n")
                    for point in loop { try resources.recordIterations(); try bounded.writeUTF8("10\n\(stepNumber(point.x))\n20\n\(stepNumber(point.y))\n") }
                    try bounded.writeUTF8("97\n0\n")
                }
                try bounded.writeUTF8("75\n0\n76\n1\n98\n0\n1001\nSWIFTCAD\n")
                try writeDXFIdentity(region.identity, to: bounded, resources: resources)
                try bounded.writeUTF8("1000\noriginalFillRGB\n1040\n\(stepNumber(options.styles.material.red))\n1040\n\(stepNumber(options.styles.material.green))\n1040\n\(stepNumber(options.styles.material.blue))\n")
            }
            for path in paths {
                try resources.checkTime()
                let style = options.styles.stroke(for: path.layer)
                let width = try options.outputLength(paperPoints: style.width)
                guard let styleIndex = options.styles.strokes.firstIndex(of: style) else {
                    throw ExportError.invalidMesh("Drawing stroke has no authored linetype record.")
                }
                if path.points.count == 1, let point = path.points.first {
                    try bounded.writeUTF8("0\nCIRCLE\n100\nAcDbEntity\n8\n\(path.layer)\n420\n\(style.trueColor)\n100\nAcDbCircle\n10\n\(stepNumber(point.x))\n20\n\(stepNumber(point.y))\n40\n\(stepNumber(width / 2))\n")
                } else {
                    try bounded.writeUTF8("0\nLWPOLYLINE\n100\nAcDbEntity\n8\n\(path.layer)\n420\n\(style.trueColor)\n6\nSWIFTCAD_STYLE_\(styleIndex)\n100\nAcDbPolyline\n90\n\(path.points.count)\n70\n128\n43\n\(stepNumber(width))\n")
                    for point in path.points { try resources.recordIterations(); try bounded.writeUTF8("10\n\(stepNumber(point.x))\n20\n\(stepNumber(point.y))\n") }
                }
                try bounded.writeUTF8("1001\nSWIFTCAD\n")
                try writeDXFIdentity(path.identity, to: bounded, resources: resources)
                try writeDXFOriginalStyle(style, to: bounded, resources: resources)
                if let descriptor = path.originalRootSpanDescriptor {
                    try writeDXFIdentity(descriptor, to: bounded, resources: resources, label: "originalAlgebraicSpanJSONUTF8Base64")
                }
                if let descriptor = path.originalSilhouetteDescriptor {
                    try writeDXFIdentity(descriptor, to: bounded, resources: resources, label: "originalSilhouetteJSONUTF8Base64")
                }
                if let descriptor = path.originalAnnotationDescriptor {
                    try writeDXFIdentity(descriptor, to: bounded, resources: resources, label: "originalAnnotationJSONUTF8Base64")
                }
                if let stations = path.nativeStations {
                    try bounded.writeUTF8("1000\noriginalNativeStations\n1071\n\(stations.count)\n")
                    for station in stations { try resources.recordIterations(); try bounded.writeUTF8("1040\n\(stepNumber(station))\n") }
                }
                if let start = path.startParameter, let end = path.endParameter {
                    try bounded.writeUTF8("1040\n\(stepNumber(start))\n1040\n\(stepNumber(end))\n")
                }
            }

            for glyph in glyphs {
                try writeDXFGlyph(glyph, resolved: resolvedGlyphBoundaries[glyph.identity],
                    maximumDeviation: maximumGlyphDeviation, options: options, to: bounded, resources: resources, using: &execution)
            }
            try bounded.writeUTF8("0\nENDSEC\n0\nEOF\n")
        case .svg:
            try bounded.writeUTF8("<svg xmlns=\"http://www.w3.org/2000/svg\" data-unit=\"\(options.outputUnit.rawValue)\" viewBox=\"0 0 \(stepNumber(options.pageWidth)) \(stepNumber(options.pageHeight))\">\n<g fill=\"none\" transform=\"translate(0 \(stepNumber(options.pageHeight))) scale(1 -1)\">\n")
            for region in regions {
                let sourceIdentity = try xmlAttribute(region.identity, resources: resources)
                try bounded.writeUTF8("<path data-source-id=\"\(sourceIdentity)\" fill=\"\(svgColor(options.styles.material.red, options.styles.material.green, options.styles.material.blue))\" fill-rule=\"evenodd\" d=\"")
                for loop in region.loops {
                    guard let first = loop.first else { throw ExportError.invalidMesh("Empty material loop.") }
                    try bounded.writeUTF8("M \(stepNumber(first.x)) \(stepNumber(first.y)) ")
                    for point in loop.dropFirst() { try resources.recordIterations(); try bounded.writeUTF8("L \(stepNumber(point.x)) \(stepNumber(point.y)) ") }
                    try bounded.writeUTF8("Z ")
                }
                try bounded.writeUTF8("\"/>\n")
            }
            for path in paths {
                try resources.checkTime()
                let sourceIdentity = try xmlAttribute(path.identity, resources: resources)
                let style = options.styles.stroke(for: path.layer)
                let appearance = try svgStyle(style, options: options, resources: resources)
                var stationAttribute = ""
                if let descriptor = path.originalRootSpanDescriptor {
                    stationAttribute += " data-original-algebraic-span=\"\(try xmlAttribute(descriptor, resources: resources))\""
                }
                if let descriptor = path.originalSilhouetteDescriptor {
                    stationAttribute += " data-original-silhouette=\"\(try xmlAttribute(descriptor, resources: resources))\""
                }
                if let descriptor = path.originalAnnotationDescriptor {
                    stationAttribute += " data-original-annotation=\"\(try xmlAttribute(descriptor, resources: resources))\""
                }
                if let stations = path.nativeStations {
                    stationAttribute += " data-native-stations=\""
                    for station in stations { try resources.recordIterations(); stationAttribute += "\(stepNumber(station)) " }
                    stationAttribute += "\""
                    try resources.recordBytes(stationAttribute.utf8.count)
                }
                let interval: String
                if let start = path.startParameter, let end = path.endParameter {
                    guard start.isFinite, end.isFinite else { throw ExportError.invalidMesh("SVG original interval is nonfinite.") }
                    interval = " data-native-start=\"\(stepNumber(start))\" data-native-end=\"\(stepNumber(end))\""
                } else {
                    guard path.startParameter == nil, path.endParameter == nil else { throw ExportError.invalidMesh("SVG original interval is incomplete.") }
                    interval = ""
                }
                if path.points.count == 1, let point = path.points.first {
                    try bounded.writeUTF8("<circle data-source-id=\"\(sourceIdentity)\"\(interval)\(stationAttribute) cx=\"\(stepNumber(point.x))\" cy=\"\(stepNumber(point.y))\" r=\"\(stepNumber(try options.outputLength(paperPoints: style.width) / 2))\" fill=\"\(svgColor(style.red, style.green, style.blue))\"/>\n")
                } else {
                    try bounded.writeUTF8("<polyline data-source-id=\"\(sourceIdentity)\"\(interval)\(stationAttribute) data-layer=\"\(path.layer)\" \(appearance) points=\"")
                    for point in path.points { try resources.recordIterations(); try bounded.writeUTF8("\(stepNumber(point.x)),\(stepNumber(point.y)) ") }
                    try bounded.writeUTF8("\"/>\n")
                }
            }

            for glyph in glyphs { try writeSVGGlyph(glyph, options: options, to: bounded, resources: resources) }
            try bounded.writeUTF8("</g>\n</svg>\n")
        case .pdf:
            let gain = options.outputUnit.metersPerUnit * 72 / 0.0254
            var pagePaths: [BRepDrawingOutputPath] = []
            for path in paths {
                try resources.recordIterations(options.styles.stroke(for: path.layer).dashPattern.count + 1)
                try resources.recordBytes(path.points.count * MemoryLayout<Point2D>.stride)
                var page: [Point2D] = []
                for point in path.points {
                    try resources.recordIterations()
                    let value = Point2D(x: point.x * gain,y: point.y * gain)
                    guard value.x.isFinite, value.y.isFinite else { throw ExportError.invalidMesh("PDF coordinate overflow.") }
                    page.append(value)
                }
                pagePaths.append(.init(points: page, layer: path.layer, identity: path.identity,
                    startParameter: path.startParameter, endParameter: path.endParameter, nativeStations: path.nativeStations, originalRootSpanPath: path.originalRootSpanPath, originalRootSpanDescriptor: path.originalRootSpanDescriptor, originalSilhouettePath: path.originalSilhouettePath, originalSilhouetteDescriptor: path.originalSilhouetteDescriptor, originalSilhouettePoint: path.originalSilhouettePoint, originalAnnotationDescriptor: path.originalAnnotationDescriptor))
            }
            var pageRegions: [BRepDrawingOutputRegion] = []
            for region in regions {
                var loops: [[Point2D]] = []
                for loop in region.loops {
                    try resources.recordBytes(loop.count * MemoryLayout<Point2D>.stride)
                    var points: [Point2D] = []
                    for point in loop {
                        try resources.recordIterations()
                        let value = Point2D(x: point.x * gain, y: point.y * gain)
                        guard value.x.isFinite, value.y.isFinite else { throw ExportError.invalidMesh("PDF material coordinate overflow.") }
                        points.append(value)
                    }
                    loops.append(points)
                }
                pageRegions.append(.init(identity: region.identity, loops: loops, outer: region.outer))
            }
            let data = try PDFDocumentEncoder().encodeDrawing(paths: pagePaths, regions: pageRegions, glyphs: glyphs, pageWidth: options.pageWidth * gain,
                pageHeight: options.pageHeight * gain, styles: options.styles, maximumBytes: resources.limits.maximumBytes, resources: resources, using: &execution)
            try bounded.write(data)
        default: throw ImportError.unsupportedFormat(format.displayName)
        }
        try resources.checkTime(); try sink.write(output.bytes)
    }
    private func writeDXFStyles(_ options: DrawingExchangeOptions, to sink: any ByteSink,
                                resources: SharedExchangeResourceAccountant) throws {
        let styles = options.styles.strokes
        try sink.writeUTF8("0\nTABLE\n2\nLTYPE\n70\n\(styles.count)\n")
        for (index, style) in styles.enumerated() {
            try resources.recordEntities()
            let repetitions = style.dashPattern.count.isMultiple(of: 2) ? 1 : 2
            let count = style.dashPattern.count.multipliedReportingOverflow(by: repetitions)
            guard !count.overflow, count.partialValue <= 32_767 else {
                throw exchangeResourceLimitError(format: .dxf, detail: "physical dash element count exceeds the format boundary")
            }
            try resources.recordIterations(count.partialValue)
            var total = 0.0
            for length in style.dashPattern { total += try options.outputLength(paperPoints: length) }
            total *= Double(repetitions)
            guard total.isFinite else { throw ExportError.invalidMesh("DXF dash period overflows.") }
            try sink.writeUTF8("0\nLTYPE\n100\nAcDbSymbolTableRecord\n100\nAcDbLinetypeTableRecord\n2\nSWIFTCAD_STYLE_\(index)\n70\n0\n3\nPhysical paper stroke\n72\n65\n73\n\(count.partialValue)\n40\n\(stepNumber(total))\n")
            for ordinal in 0..<count.partialValue {
                let length = try options.outputLength(paperPoints: style.dashPattern[ordinal % style.dashPattern.count])
                try sink.writeUTF8("49\n\(stepNumber(ordinal.isMultiple(of: 2) ? length : -length))\n74\n0\n")
            }
        }
        try sink.writeUTF8("0\nENDTAB\n")
    }

    private func writeDXFOriginalStyle(_ style: DrawingStrokeStyle, to sink: any ByteSink,
                                       resources: SharedExchangeResourceAccountant) throws {
        try sink.writeUTF8("1000\noriginalStrokePaperPoints\n1040\n\(stepNumber(style.red))\n1040\n\(stepNumber(style.green))\n1040\n\(stepNumber(style.blue))\n1040\n\(stepNumber(style.width))\n1071\n\(style.dashPattern.count)\n")
        for length in style.dashPattern { try resources.recordIterations(); try sink.writeUTF8("1040\n\(stepNumber(length))\n") }
    }

    func svgColor(_ red: Double, _ green: Double, _ blue: Double) -> String {
        "rgb(\(stepNumber(red * 100))%,\(stepNumber(green * 100))%,\(stepNumber(blue * 100))%)"
    }
    private func svgStyle(_ style: DrawingStrokeStyle, options: DrawingExchangeOptions,
                          resources: SharedExchangeResourceAccountant) throws -> String {
        var result = "stroke=\"\(svgColor(style.red, style.green, style.blue))\" stroke-width=\"\(stepNumber(try options.outputLength(paperPoints: style.width)))\""
        if !style.dashPattern.isEmpty {
            result += " stroke-dasharray=\""
            for length in style.dashPattern {
                try resources.recordIterations()
                let token = "\(stepNumber(try options.outputLength(paperPoints: length))) "
                try resources.recordBytes(token.utf8.count)
                result += token
            }
            result += "\""
        }
        return result
    }

    func writeDXFIdentity(_ identity: String, to sink: any ByteSink,
                                  resources: SharedExchangeResourceAccountant, label: String = "identityUTF8Base64") throws {
        try resources.recordIterations(identity.utf8.count)
        try resources.recordBytes(identity.utf8.count)
        let blocks = identity.utf8.count / 3 + (identity.utf8.count % 3 == 0 ? 0 : 1)
        let encodedSize = blocks.multipliedReportingOverflow(by: 4)
        guard !encodedSize.overflow else { throw ExportError.invalidMesh("Drawing identity encoding size overflows.") }
        try resources.recordBytes(encodedSize.partialValue)
        let encoded = Data(identity.utf8).base64EncodedString()
        try sink.writeUTF8("1000\n\(label)\n")
        var start = encoded.startIndex
        while start < encoded.endIndex {
            try resources.recordIterations()
            let end = encoded.index(start, offsetBy: 255, limitedBy: encoded.endIndex) ?? encoded.endIndex
            try sink.writeUTF8("1000\n\(encoded[start..<end])\n")
            start = end
        }
    }

    func xmlAttribute(_ value: String, resources: SharedExchangeResourceAccountant) throws -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            try resources.recordIterations()
            let encoded: String
            switch scalar.value {
            case 0x26: encoded = "&amp;"
            case 0x22: encoded = "&quot;"
            case 0x3c: encoded = "&lt;"
            case 0x3e: encoded = "&gt;"
            case 0x09, 0x0a, 0x0d: encoded = "&#\(scalar.value);"
            case 0x20...0xd7ff, 0xe000...0xfffd, 0x10000...0x10ffff: encoded = String(scalar)
            default: throw ExportError.invalidMesh("Drawing source identity contains an XML-invalid scalar.")
            }
            try resources.recordBytes(encoded.utf8.count)
            result += encoded
        }
        return result
    }

    private func unitCode(_ unit: LengthUnit) -> Int {
        switch unit { case .inch: 1; case .millimeter: 4; case .centimeter: 5; case .meter: 6; case .foot: 2; case .micrometer: 13; case .kilometer: 7 }
    }
}
