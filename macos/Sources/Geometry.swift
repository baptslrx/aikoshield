import CoreGraphics

/// Partie visible d'une fenêtre : son cadre moins les fenêtres placées devant.
func subtractRects(_ rect: CGRect, _ holes: [CGRect]) -> [CGRect] {
    var pieces = [rect]
    for h in holes {
        var next: [CGRect] = []
        for p in pieces {
            let i = p.intersection(h)
            if i.isNull || i.isEmpty { next.append(p); continue }
            if i.maxY < p.maxY { next.append(CGRect(x: p.minX, y: i.maxY, width: p.width, height: p.maxY - i.maxY)) }
            if i.minY > p.minY { next.append(CGRect(x: p.minX, y: p.minY, width: p.width, height: i.minY - p.minY)) }
            if i.minX > p.minX { next.append(CGRect(x: p.minX, y: i.minY, width: i.minX - p.minX, height: i.height)) }
            if i.maxX < p.maxX { next.append(CGRect(x: i.maxX, y: i.minY, width: p.maxX - i.maxX, height: i.height)) }
        }
        pieces = next.filter { $0.width > 1 && $0.height > 1 }
        if pieces.isEmpty { break }
    }
    return pieces
}
