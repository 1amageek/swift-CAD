import CADCore
import CADGeometry
import CADKernel

extension BRepDrawingExchange {
    func writeDXFResolvedGlyph(_ receipt: DrawingResolvedGlyphBoundary, maximumDeviation: Double,
                              options: DrawingExchangeOptions, to sink: any ByteSink,
                              resources: inout SharedExchangeResourceAccountant) throws {
        let glyph = receipt.original
        let loops = try ResolvedGlyphBoundaryLinearizer().linearize(receipt.boundary,
            maximumDeviation: maximumDeviation, resources: resources)
        if loops.isEmpty {
            // Exact winding cancellation has no visible material. Retain its source on a whitespace text entity.
            try sink.writeUTF8("0\nTEXT\n100\nAcDbEntity\n8\nAnnotation\n100\nAcDbText\n10\n0\n20\n0\n40\n\(stepNumber(try options.outputLength(paperPoints: glyph.fontSize)))\n1\n \n")
        } else {
            try sink.writeUTF8("0\nHATCH\n100\nAcDbEntity\n8\nAnnotation\n420\n\(options.styles.annotation.trueColor)\n100\nAcDbHatch\n10\n0\n20\n0\n30\n0\n210\n0\n220\n0\n230\n1\n2\nSOLID\n70\n1\n71\n0\n91\n\(loops.count)\n")
            for loop in loops {
                guard loop.count >= 4, loop.first == loop.last else {
                    throw ExportError.invalidMesh("Resolved glyph loop has no valid closed publication polygon.")
                }
                // Only the polyline bit is set; no rounded outer/hole classification is invented.
                try sink.writeUTF8("92\n2\n72\n0\n73\n1\n93\n\(loop.count-1)\n")
                for point in loop.dropLast() {
                    try resources.recordIterations()
                    let output = try paperPoint(point, outputUnit: options.outputUnit)
                    try sink.writeUTF8("10\n\(stepNumber(output.x))\n20\n\(stepNumber(output.y))\n")
                }
                try sink.writeUTF8("97\n0\n")
            }
            try sink.writeUTF8("75\n0\n76\n1\n98\n0\n")
        }
        try writeDXFGlyphProvenance(glyph, to: sink, resources: &resources)
        try sink.writeUTF8("1000\nresolvedOriginalNonzeroBoundary\n1000\nmaximumGlyphDeviationPaperPoints\n1040\n\(stepNumber(maximumDeviation))\n")
        for loop in receipt.boundary.loops {
            for use in loop.uses {
                try resources.recordIterations()
                try sink.writeUTF8("1000\noriginalBoundarySegmentID\n1000\n\(use.sourceSegmentID)\n1000\noriginalBoundaryForward\n1070\n\(use.forward ? 1 : 0)\n")
            }
        }
    }
}
