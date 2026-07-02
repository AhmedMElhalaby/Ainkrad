enum SplitAxis: Equatable {
    case horizontal
    case vertical
}

/// A binary split tree of Blocks — the non-overlapping tile layout for one
/// workspace. A `.split` never overlaps its children; there is no floating,
/// no z-order, no drop shadow.
indirect enum TileNode: Equatable {
    case leaf(Block)
    case split(axis: SplitAxis, ratio: Double, first: TileNode, second: TileNode)
}
