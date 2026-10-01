import CADCore
import CADIR
import CADTopology

/// Sews sheet bodies into one body along the edges where they meet exactly.
///
/// Every pair of boundary edges that coincide within the modeling tolerance becomes one shared
/// edge, an edge first split where another sheet's edge ends inside it so that edges sharing part
/// of their length pair along it; the sheets must all meet, each one sharing an edge with the rest, and must be orientable
/// together, their faces reoriented to agree with the first sheet. When `closed`, the shell must
/// have no boundary edge left and bounds a solid whose faces face out of it; otherwise it must
/// keep one and the result is a sheet. The sources stay in the model; the caller replaces them
/// with the result.
public protocol SheetBodyJoining: Sendable {
    func joinSheets(
        bodyIDs: [BodyID],
        closed: Bool,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BRepSewingResult
}
