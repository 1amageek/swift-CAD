import CADCore
import CADIR

public struct SketchBuilder {
    private var sketch: Sketch

    public init(on plane: SketchPlane) {
        self.sketch = Sketch(plane: plane)
    }

    public mutating func point(x: CADExpression, y: CADExpression) -> SketchEntityID {
        let id = SketchEntityID()
        sketch.entities[id] = .point(SketchPoint(x: x, y: y))
        sketch.entityOrder.append(id)
        return id
    }

    public mutating func line(from start: SketchPoint, to end: SketchPoint) -> SketchEntityID {
        let id = SketchEntityID()
        sketch.entities[id] = .line(SketchLine(start: start, end: end))
        sketch.entityOrder.append(id)
        return id
    }

    @discardableResult
    public mutating func circle(center: SketchPoint, radius: CADExpression) -> SketchEntityID {
        let id = SketchEntityID()
        sketch.entities[id] = .circle(SketchCircle(center: center, radius: radius))
        sketch.entityOrder.append(id)
        return id
    }

    @discardableResult
    public mutating func arc(
        center: SketchPoint,
        radius: CADExpression,
        startAngle: CADExpression,
        endAngle: CADExpression
    ) -> SketchEntityID {
        let id = SketchEntityID()
        sketch.entities[id] = .arc(SketchArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle
        ))
        sketch.entityOrder.append(id)
        return id
    }

    @discardableResult
    public mutating func spline(_ spline: SketchSpline) -> SketchEntityID {
        let id = SketchEntityID()
        sketch.entities[id] = .spline(spline)
        sketch.entityOrder.append(id)
        return id
    }

    @discardableResult
    public mutating func rectangle(width: CADExpression, height: CADExpression) -> [SketchEntityID] {
        let two = CADExpression.scalar(2.0)
        let minusOne = CADExpression.scalar(-1.0)
        let halfWidth = CADExpression.divide(width, two)
        let halfHeight = CADExpression.divide(height, two)
        let negativeHalfWidth = CADExpression.multiply(minusOne, halfWidth)
        let negativeHalfHeight = CADExpression.multiply(minusOne, halfHeight)

        let bottomLeft = SketchPoint(x: negativeHalfWidth, y: negativeHalfHeight)
        let bottomRight = SketchPoint(x: halfWidth, y: negativeHalfHeight)
        let topRight = SketchPoint(x: halfWidth, y: halfHeight)
        let topLeft = SketchPoint(x: negativeHalfWidth, y: halfHeight)

        let bottom = line(from: bottomLeft, to: bottomRight)
        let right = line(from: bottomRight, to: topRight)
        let top = line(from: topRight, to: topLeft)
        let left = line(from: topLeft, to: bottomLeft)

        sketch.constraints.append(.horizontal(bottom))
        sketch.constraints.append(.vertical(right))
        sketch.constraints.append(.horizontal(top))
        sketch.constraints.append(.vertical(left))
        sketch.constraints.append(.coincident(.lineEnd(bottom), .lineStart(right)))
        sketch.constraints.append(.coincident(.lineEnd(right), .lineStart(top)))
        sketch.constraints.append(.coincident(.lineEnd(top), .lineStart(left)))
        sketch.constraints.append(.coincident(.lineEnd(left), .lineStart(bottom)))
        return [bottom, right, top, left]
    }

    public func build() -> Sketch {
        sketch
    }
}
