import CADCore
import CADGeometry
import CADKernel

/// An immutable filled-boundary receipt bound to the complete original shaped outline.
public struct DrawingResolvedGlyphBoundary: Sendable {
    public let original: DrawingGlyphOutline
    public let boundary: OriginalPlanarNonzeroBoundary

    public init(original: DrawingGlyphOutline, boundary: OriginalPlanarNonzeroBoundary,
                usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws {
        try usage.validateExecution(execution)
        guard original.fillRule == .nonzero, boundary.plane.origin.z == 0,
              boundary.plane.normal.x == 0, boundary.plane.normal.y == 0,
              boundary.plane.normal.z != 0 else {
            throw ExportError.invalidMesh("Resolved glyph boundary requires its original nonzero paper-plane law.")
        }
        try BRepDrawingExchange(resourceLimits: usage.resources.limits).validateGlyph(original, resources: usage.resources)
        var contourIndex = 0, segmentIndex = 0
        var start: Point2D?, current: Point2D?
        func match(_ controls: [Point2D], usage: DrawingExchangeOwner, using execution: inout OriginalQueryExecution) throws {
            guard boundary.source.contours.indices.contains(contourIndex),
                  boundary.source.contours[contourIndex].segments.indices.contains(segmentIndex) else {
                throw ExportError.invalidMesh("Resolved glyph boundary omitted an original contour edge.")
            }
            let segment = boundary.source.contours[contourIndex].segments[segmentIndex]
            let curve = segment.curve
            try usage.charge(work: controls.count + curve.controlPoints.count + curve.knots.count + curve.weights.count)
            guard !segment.reversed, curve.degree == controls.count - 1, !curve.isPeriodic,
                  curve.controlPoints.count == controls.count, curve.weights.count == controls.count,
                  curve.knots.count == controls.count * 2 else {
                throw ExportError.invalidMesh("Resolved glyph boundary changed its original Bezier source family.")
            }
            for index in controls.indices {
                let point = curve.controlPoints[index], expected = controls[index]
                guard point.x == expected.x, point.y == expected.y, point.z == 0,
                      curve.weights[index] == 1, curve.knots[index] == 0,
                      curve.knots[index + controls.count] == 1 else {
                    throw ExportError.invalidMesh("Resolved glyph boundary is bound to different original controls.")
                }
            }
            segmentIndex += 1
        }
        for command in original.commands {
            try usage.charge(work: 1, bytes: 4 * MemoryLayout<Point2D>.stride)
            switch command {
            case .move(let point): start = point; current = point; segmentIndex = 0
            case .line(let end):
                guard let from = current else { throw ExportError.invalidMesh("Glyph edge has no current original point.") }
                try match([from, end], usage: usage, using: &execution); current = end
            case .quadratic(let control, let end):
                guard let from = current else { throw ExportError.invalidMesh("Glyph quadratic has no current original point.") }
                try match([from, control, end], usage: usage, using: &execution); current = end
            case .cubic(let first, let second, let end):
                guard let from = current else { throw ExportError.invalidMesh("Glyph cubic has no current original point.") }
                try match([from, first, second, end], usage: usage, using: &execution); current = end
            case .close:
                guard let first = start, let last = current else { throw ExportError.invalidMesh("Glyph close has no original start.") }
                if last != first { try match([last, first], usage: usage, using: &execution) }
                guard boundary.source.contours.indices.contains(contourIndex),
                      segmentIndex == boundary.source.contours[contourIndex].segments.count else {
                    throw ExportError.invalidMesh("Resolved glyph boundary added a foreign contour edge.")
                }
                contourIndex += 1
                current = nil; start = nil
            }
        }
        guard contourIndex == boundary.source.contours.count else {
            throw ExportError.invalidMesh("Resolved glyph boundary added foreign original contours.")
        }
        self.original = original; self.boundary = boundary
    }

    func matches(_ glyph: DrawingGlyphOutline, resources: SharedExchangeResourceAccountant) throws -> Bool {
        try resources.recordIterations(original.text.utf8.count + glyph.text.utf8.count
            + original.fontPostScriptName.utf8.count + glyph.fontPostScriptName.utf8.count
            + original.identity.utf8.count + glyph.identity.utf8.count + original.commands.count + glyph.commands.count)
        return original.text.utf8.elementsEqual(glyph.text.utf8)
            && original.fontPostScriptName.utf8.elementsEqual(glyph.fontPostScriptName.utf8)
            && original.identity.utf8.elementsEqual(glyph.identity.utf8)
            && original.fontSize == glyph.fontSize && original.fillRule == glyph.fillRule
            && original.commands == glyph.commands
    }
}
