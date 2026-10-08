/// Original binary affine frame and origin; no exact orthonormality assumption.
public protocol OriginalImageFrameReading: Sendable {
    func center(in axis: Int) -> Double
    func frame(row: Int, column: Int) -> Double
}
