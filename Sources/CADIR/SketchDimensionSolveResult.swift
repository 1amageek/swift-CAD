public struct SketchDimensionSolveResult: Codable, Sendable {
    public var sketch: Sketch
    public var before: SketchDimensionEvaluation
    public var after: SketchDimensionEvaluation
    public var steps: [SketchDimensionSolveStep]

    public init(
        sketch: Sketch,
        before: SketchDimensionEvaluation,
        after: SketchDimensionEvaluation,
        steps: [SketchDimensionSolveStep]
    ) {
        self.sketch = sketch
        self.before = before
        self.after = after
        self.steps = steps
    }
}
