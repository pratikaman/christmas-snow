import Cocoa
import ImageIO

struct DockRoute {
    let start: CGPoint
    let end: CGPoint
    var horizontal: Bool { abs(end.x-start.x) >= abs(end.y-start.y) }
    func local(to screen:CGRect) -> DockRoute? {
        let mid = CGPoint(x:(start.x+end.x)/2,y:(start.y+end.y)/2)
        guard screen.contains(mid) else { return nil }
        func convert(_ p:CGPoint) -> CGPoint { CGPoint(x:p.x-screen.minX,y:p.y-screen.minY) }
        return DockRoute(start:convert(start), end:convert(end))
    }
}

enum SantaSize: String, CaseIterable {
    case tiny = "Tiny"
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var scale: CGFloat {
        switch self {
        case .tiny: return 0.7
        case .small: return 1
        case .medium: return 1.5
        case .large: return 2
        }
    }
}

final class DockSantas {
    private struct Walker {
        let layer = CALayer()
        let height: CGFloat
        let speed: CGFloat
        var t: CGFloat
        var direction: CGFloat
        var animation: CGFloat = 0
        var resting: CGFloat = 0
        var lastFrame = -1
    }
    private var walkers = [
        Walker(height:30,speed:17,t:0.12,direction:1),
        Walker(height:34,speed:22,t:0.51,direction:-1),
        Walker(height:27,speed:15,t:0.86,direction:1)
    ]
    private static func frames(_ stem:String,_ count:Int) -> [CGImage] {
        (0..<count).compactMap { i in
            let name = String(format:"%@-%02d",stem,i)
            guard let url = Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"Santa"),
                  let source = CGImageSourceCreateWithURL(url as CFURL,nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
        }
    }
    private static let walk = frames("walk",13)
    private static let idle = frames("idle",16)
    let container = CALayer()
    var route: DockRoute?
    var enabled = true
    var size: SantaSize = .small

    init() {
        container.zPosition = 2
        for w in walkers {
            w.layer.magnificationFilter = .linear
            w.layer.minificationFilter = .trilinear
            container.addSublayer(w.layer)
        }
    }

    func update(dt: CGFloat, dockSnow:[Drift]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard enabled, let route, !Self.walk.isEmpty, !Self.idle.isEmpty else {
            container.isHidden = true
            return
        }
        container.isHidden = false
        let dx = route.end.x-route.start.x, dy = route.end.y-route.start.y
        let length = max(1,hypot(dx,dy))
        let count = min(walkers.count,max(1,Int(length/80)))
        for i in walkers.indices {
            var w = walkers[i]
            w.layer.isHidden = i >= count
            if i >= count { continue }
            // Each Santa patrols a stretch of the Dock and rests before turning.
            let low = (CGFloat(i)+0.04)/CGFloat(count)
            let high = (CGFloat(i)+0.96)/CGFloat(count)
            w.t = min(high,max(low,w.t))
            if w.resting > 0 {
                w.resting = max(0,w.resting-dt)
            } else {
                w.t += w.direction*w.speed*dt/length
                if w.t <= low || w.t >= high {
                    w.t = min(high,max(low,w.t))
                    w.direction *= -1
                    w.resting = .random(in:1...3)
                    w.animation = 0
                }
            }
            w.animation += dt*(w.resting > 0 ? 8 : w.speed*0.65)
            let sequence = w.resting > 0 ? Self.idle : Self.walk
            let frame = Int(w.animation) % sequence.count
            let token = frame+(w.resting > 0 ? 100:0)
            let image = sequence[frame]
            if w.lastFrame != token {
                w.layer.contents = image
                w.layer.bounds = CGRect(x:0,y:0,width:w.height*CGFloat(image.width)/CGFloat(image.height),height:w.height)
                w.lastFrame = token
            }
            let x = route.start.x+dx*w.t
            var foot = route.start.y+dy*w.t
            if route.horizontal, let drift = dockSnow.first(where:{ $0.shelf.left <= x && x <= $0.shelf.right }) {
                foot = drift.shelf.y - drift.depths[drift.bin(x)] + 0.5
            }
            let scale = size.scale
            w.layer.position = CGPoint(x:x,y:foot-w.height*scale/2)
            w.layer.transform = CATransform3DMakeScale(w.direction*scale,scale,1)
            walkers[i] = w
        }
    }
}
