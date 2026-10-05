import CADCore

extension BRepDrawingExchange {
    public func write(_ page: DrawingExchangePage, as format: ExchangeFileFormat,
                      outputUnit: LengthUnit = .millimeter, usage: inout DrawingExchangeUsage,
                      to sink: any ByteSink) throws {
        guard usage.resources.format == format, [.dxf, .svg, .pdf].contains(format),
              page.width.isFinite, page.height.isFinite, page.width > 0, page.height > 0,
              page.maximumGlyphDeviation.isFinite, page.maximumGlyphDeviation > 0 else {
            throw ExportError.invalidMesh("Invalid page format, physical size, glyph allowance or shared drawing ledger.")
        }
        try usage.check()
        for style in page.styles.strokes { try usage.charge(work: style.dashPattern.count + 1) }
        try page.styles.validate()
        try usage.charge(entities: page.paths.count + page.regions.count + page.glyphs.count)
        try usage.charge(bytes: page.paths.count * MemoryLayout<BRepDrawingOutputPath>.stride)
        var paths: [BRepDrawingOutputPath] = []
        paths.reserveCapacity(page.paths.count)
        let options = DrawingExchangeOptions(outputUnit: outputUnit,
            pageWidth: try paperLength(page.width, outputUnit: outputUnit),
            pageHeight: try paperLength(page.height, outputUnit: outputUnit), styles: page.styles)
        for path in page.paths {
            try usage.charge(work: path.points.count + path.identity.utf8.count)
            guard !path.identity.isEmpty, !path.points.isEmpty else { throw ExportError.invalidMesh("Page path lacks geometry or original identity.") }
            var originalDescriptor: String?
            var silhouetteDescriptor: String?
            var annotationDescriptor: String?
            let originalCount = (path.originalRootSpanPath == nil ? 0 : 1) + (path.originalSilhouettePath == nil ? 0 : 1) + (path.originalSilhouettePoint == nil ? 0 : 1) + (path.originalRadialDimension == nil ? 0 : 1)
            guard originalCount <= 1 else {
                throw ExportError.invalidMesh("Page path has competing original curve receipts.")
            }
            if let original = path.originalRadialDimension {
                guard usage.sharesAccountingOwner(with: original.accountingOwner),
                    path.role == .annotation, path.identity.utf8.elementsEqual(original.identity.utf8),
                    path.originalParameters == nil else {
                    throw ExportError.invalidMesh("Radial dimension stroke differs from its original annotation source or invocation.")
                }
                let data = try NativeBoundedJSONEncoder().encode(DrawingOriginalRadialDimensionDescriptor(original), resources: usage.resources)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ExportError.invalidMesh("Original radial dimension descriptor is not UTF-8.")
                }
                annotationDescriptor = text
            }
            if let original = path.originalSilhouettePoint {
                guard original.admission.belongsToSameInvocation(as: usage, silhouetteUsage: original.silhouetteOwner),
                    path.originalParameters == nil, path.points.count == 1, path.points.first == original.point else {
                    throw ExportError.invalidMesh("Page silhouette point differs from its complete original source receipt.")
                }
                silhouetteDescriptor = try DrawingOriginalSilhouettePointDescriptor.complete(original, usage: &usage)
            }
            if let original = path.originalSilhouettePath {
                try usage.charge(work: original.samples.count)
                guard original.admission.belongsToSameInvocation(as: usage, silhouetteUsage: original.silhouetteOwner),
                    path.originalParameters == nil, path.points.count == original.samples.count else {
                    throw ExportError.invalidMesh("Page silhouette must retain its original invocation without invented native endpoint stations.")
                }
                for index in path.points.indices {
                    guard path.points[index] == original.samples[index].point else {
                        throw ExportError.invalidMesh("Page silhouette points differ from their original chord receipt.")
                    }
                }
                silhouetteDescriptor = try DrawingOriginalSilhouetteDescriptor.complete(original, usage: &usage)
            }
            if let original = path.originalRootSpanPath {
                try usage.charge(work: original.samples.count)
                guard usage.sharesAccountingOwner(with: original.accountingOwner), path.originalParameters == nil, original.samples.count == path.points.count else {
                    throw ExportError.invalidMesh("Algebraic page span must retain its original receipt without invented native endpoint stations.")
                }
                for index in path.points.indices {
                    guard path.points[index] == original.samples[index].point else {
                        throw ExportError.invalidMesh("Page points differ from their original root-span chord receipt.")
                    }
                }
                let descriptor = DrawingOriginalRootSpanDescriptor(span: original.span, operationWord: original.operationWord,
                    maximumDeviationPaperPoints: original.maximumDeviation)
                let data = try NativeBoundedJSONEncoder().encode(descriptor, resources: usage.resources)
                guard let text = String(data: data, encoding: .utf8) else { throw ExportError.invalidMesh("Original span descriptor is not valid UTF-8.") }
                originalDescriptor = text
            }
            if let stations = path.originalParameters {
                try usage.charge(work: stations.count)
                guard stations.count == path.points.count, stations.allSatisfy({ $0.isFinite }) else {
                    throw ExportError.invalidMesh("Page native stations disagree with original path samples.")
                }
            }
            try usage.charge(bytes: path.points.count * MemoryLayout<Point2D>.stride)
            var points: [Point2D] = []
            points.reserveCapacity(path.points.count)
            for point in path.points {
                guard point.x.isFinite, point.y.isFinite else { throw ExportError.invalidMesh("Page path point is nonfinite.") }
                points.append(format == .pdf ? point : try paperPoint(point, outputUnit: outputUnit))
            }
            paths.append(.init(points: points, layer: path.role.rawValue, identity: path.identity,
                startParameter: path.originalParameters?.first, endParameter: path.originalParameters?.last,
                nativeStations: path.originalParameters, originalRootSpanPath: path.originalRootSpanPath, originalRootSpanDescriptor: originalDescriptor, originalSilhouettePath: path.originalSilhouettePath, originalSilhouetteDescriptor: silhouetteDescriptor, originalSilhouettePoint: path.originalSilhouettePoint, originalAnnotationDescriptor: annotationDescriptor))
        }
        var regions: [BRepDrawingOutputRegion] = []
        for region in page.regions {
            try usage.charge(work: region.loops.count + region.identity.utf8.count)
            guard !region.identity.isEmpty, region.loops.count == region.outer.count,
                  region.outer.filter({ $0 }).count == 1 else { throw ExportError.invalidMesh("Page region original contour partition is invalid.") }
            var loops: [[Point2D]] = []
            for loop in region.loops {
                try usage.charge(work: loop.count, bytes: loop.count * MemoryLayout<Point2D>.stride)
                guard loop.count >= 4, let first = loop.first, let last = loop.last,
                      first == last else { throw ExportError.invalidMesh("Page material contour is not explicitly closed.") }
                var points: [Point2D] = []
                for point in loop {
                    guard point.x.isFinite, point.y.isFinite else { throw ExportError.invalidMesh("Page material point is nonfinite.") }
                    points.append(format == .pdf ? point : try paperPoint(point, outputUnit: outputUnit))
                }
                loops.append(points)
            }
            regions.append(.init(identity: region.identity, loops: loops, outer: region.outer))
        }
        try usage.charge(entities: page.resolvedGlyphBoundaries.count,
            bytes: page.resolvedGlyphBoundaries.count * MemoryLayout<(String, DrawingResolvedGlyphBoundary)>.stride)
        var boundaries: [String: DrawingResolvedGlyphBoundary] = [:]
        for receipt in page.resolvedGlyphBoundaries {
            try usage.charge(work: receipt.original.identity.utf8.count + 1)
            guard boundaries[receipt.original.identity] == nil else { throw ExportError.invalidMesh("Page has duplicate original glyph boundary identities.") }
            boundaries[receipt.original.identity] = receipt
        }
        var matchedBoundaryCount = 0
        for glyph in page.glyphs {
            try validateGlyph(glyph, resources: &usage.resources)
            if let receipt = boundaries[glyph.identity] {
                guard try receipt.matches(glyph, resources: usage.resources) else { throw ExportError.invalidMesh("Page glyph boundary belongs to a different shaped source.") }
                matchedBoundaryCount += 1
            }
        }
        guard matchedBoundaryCount == boundaries.count else { throw ExportError.invalidMesh("Page has foreign or multiply selected glyph boundary receipts.") }
        if format == .pdf {
            let bytes = try PDFDocumentEncoder().encodeDrawing(paths: paths, regions: regions, glyphs: page.glyphs,
                pageWidth: page.width, pageHeight: page.height, styles: page.styles,
                maximumBytes: usage.resources.limits.maximumBytes,
                maximumGlyphDeviation: page.maximumGlyphDeviation, resources: &usage.resources)
            let output = DataByteSink()
            let bounded = try ExchangeBoundedByteSink(downstream: output, limits: usage.resources.limits, format: format)
            try bounded.write(bytes); try usage.check(); try sink.write(output.bytes)
        } else {
            try publish(paths, regions: regions, glyphs: page.glyphs,
                resolvedGlyphBoundaries: boundaries, maximumGlyphDeviation: page.maximumGlyphDeviation, as: format,
                options: options, resources: &usage.resources, to: sink)
        }
    }

    func paperLength(_ value: Double, outputUnit: LengthUnit) throws -> Double {
        let result = outputUnit.fromInternal(value * (0.0254 / 72))
        guard result.isFinite else { throw ExportError.invalidMesh("Page physical coordinate overflows.") }
        return result
    }
    func paperPoint(_ point: Point2D, outputUnit: LengthUnit) throws -> Point2D {
        Point2D(x: try paperLength(point.x, outputUnit: outputUnit), y: try paperLength(point.y, outputUnit: outputUnit))
    }
}
