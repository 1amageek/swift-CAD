/// Ordinals address the retained relation pair and its certified selected cell.
public struct OriginalIssuedCurveSurfacePointIncidence: Sendable {
    public let pairIndex: Int
    public let selectedCellIndex: Int
    let coordinateOffset: Int
    init(pairIndex: Int, selectedCellIndex: Int, coordinateOffset: Int) {
        self.pairIndex = pairIndex; self.selectedCellIndex = selectedCellIndex
        self.coordinateOffset = coordinateOffset
    }
}
