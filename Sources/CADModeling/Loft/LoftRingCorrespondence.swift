import CADCore
import CADGeometry

/// The immutable selected traversal and point correspondence of each original section.
package struct LoftRingCorrespondence {
    package let rings: [[Point3D]]
    package let reversals: [Bool]
}
