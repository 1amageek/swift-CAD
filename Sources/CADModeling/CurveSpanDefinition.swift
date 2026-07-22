import CADCore
import CADGeometry

package struct CurveSpanDefinition: Sendable {
    package let curve: Curve3D
    package let startParameter: Double
    package let endParameter: Double
    package let startPoint: Point3D
    package let endPoint: Point3D

    package init(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        startPoint: Point3D,
        endPoint: Point3D
    ) {
        self.curve = curve
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    package init(_ edge: BRepSewingEdge) {
        self.init(
            curve: edge.curve,
            startParameter: edge.startParameter,
            endParameter: edge.endParameter,
            startPoint: edge.startPoint,
            endPoint: edge.endPoint
        )
    }
}
