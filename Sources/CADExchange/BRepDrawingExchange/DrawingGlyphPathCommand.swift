import CADCore

/// Original resolved glyph outline commands, in final paper points.
public enum DrawingGlyphPathCommand: Equatable, Sendable {
    case move(Point2D)
    case line(Point2D)
    case quadratic(control: Point2D, end: Point2D)
    case cubic(firstControl: Point2D, secondControl: Point2D, end: Point2D)
    case close
}
