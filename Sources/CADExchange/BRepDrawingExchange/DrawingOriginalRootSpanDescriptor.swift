import Foundation
import CADGeometry

/// Native original endpoint and operation law, excluding chord proposals and prepared caches.
struct DrawingOriginalRootSpanDescriptor: Encodable {
    let span: OriginalCurveRootSpan3D
    let operationWord: OriginalAffineOperationWord
    let maximumDeviationPaperPoints: Double
}
