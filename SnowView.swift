import Cocoa

struct Flake {
    var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
    var size: CGFloat, fall: CGFloat, phase: CGFloat
    var style: Int
}

final class Drift {
    var shelf: Shelf
    var depths: [CGFloat] = []
    let shape = CAShapeLayer()
    var changed = true
    private let crestPhase = CGFloat.random(in:0...6)
    static let step: CGFloat = 5
    init(_ shelf: Shelf) {
        self.shelf = shelf
        shape.fillColor = CGColor(red:0.94,green:0.975,blue:1,alpha:0.97)
        shape.shadowColor = CGColor(red:0.22,green:0.37,blue:0.52,alpha:1)
        shape.shadowOpacity = 0.48
        shape.shadowOffset = CGSize(width:0,height:0.8)
        shape.shadowRadius = 0.9
        update(shelf)
        // A dusting on first appearance makes ledges visible from the first frame.
        let seed = CGFloat.random(in:0...6)
        for i in depths.indices {
            depths[i] = max(0, sin(CGFloat(i)*0.19+seed) * 0.7 + sin(CGFloat(i)*0.39)*0.25 + 0.4)
        }
    }
    func update(_ s: Shelf) {
        if shelf.left != s.left || shelf.right != s.right || shelf.y != s.y { changed = true }
        shelf = s
        let count = max(2,Int(ceil((s.right-s.left)/Self.step))+1)
        if depths.count > count { depths.removeLast(depths.count-count) }
        if depths.count < count { depths += Array(repeating:0,count:count-depths.count) }
    }
    func deposit(_ i:Int, amount:CGFloat) {
        changed = true
        for j in max(0,i-2)...min(i+2,depths.count-1) {
            let x = CGFloat(j)
            let crest = 5.6 + 2.3*sin(x*0.24+crestPhase) + 1.3*sin(x*0.57+2*crestPhase)
            depths[j] = min(crest,depths[j]+amount*(1-0.30*CGFloat(abs(i-j))))
        }
    }
    func bin(_ x:CGFloat) -> Int { min(depths.count-1,max(0,Int((x-shelf.left)/Self.step))) }
}

final class SnowView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    private(set) var flakes: [Flake] = []
    private(set) var drifts: [Drift] = []
    private var emission: CGFloat = 0
    private var time: CGFloat = 0
    private var previousMouse: CGPoint?
    private var motionCooldown: CGFloat = 0
    var density: CGFloat = 1
    let santas = DockSantas()
    let peekers = PeekingSantas()
    private var dockSnow: [Drift] = []
    private let field = CALayer()
    private var spriteLayers: [CALayer] = []
    private var spriteStyles: [Int] = []

    override init(frame: NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        field.frame = bounds
        field.addSublayer(santas.container)
        field.addSublayer(peekers.container)
        layer?.addSublayer(field)
    }
    required init?(coder:NSCoder) { fatalError("SnowView is created programmatically") }

    private static let sprites: [CGImage] = (0..<6).map { kind in
        let n = 56
        let ctx = CGContext(data:nil,width:n,height:n,bitsPerComponent:8,bytesPerRow:0,
                            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x:28,y:28)
        ctx.setShadow(offset:.zero, blur:2.5, color:CGColor(red:0.26,green:0.42,blue:0.58,alpha:0.72))
        let color = CGColor(red:kind%2==0 ? 1:0.89,green:kind%2==0 ? 1:0.95,blue:1,alpha:kind==0 ? 0.63:0.96)
        ctx.setFillColor(color)
        if kind < 3 {
            ctx.fillEllipse(in:CGRect(x:-17,y:-17,width:34,height:34))
        } else {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(2.6); ctx.setLineCap(.round)
            ctx.rotate(by:CGFloat(kind)*0.27)
            for _ in 0..<6 {
                ctx.move(to:.zero); ctx.addLine(to:CGPoint(x:0,y:22))
                for y in [9,15] {
                    ctx.move(to:CGPoint(x:-4.4,y:CGFloat(y)+4)); ctx.addLine(to:CGPoint(x:0,y:y))
                    ctx.addLine(to:CGPoint(x:4.4,y:CGFloat(y)+4))
                }
                ctx.rotate(by:.pi/3)
            }
            ctx.strokePath()
        }
        return ctx.makeImage()!
    }

    func flake(x:CGFloat,y:CGFloat) -> Flake {
        let style = Int.random(in:0..<100)
        let k = style < 27 ? Int.random(in:3...5) : Int.random(in:0...2)
        let size = k >= 3 ? CGFloat.random(in:8...15) : CGFloat.random(in:2.5...6)
        let fall = CGFloat.random(in:21...48)+size*1.5
        return Flake(x:x,y:y,vx:.random(in:-10...10),vy:fall,size:size,fall:fall,phase:.random(in:0...6.28),style:k)
    }
    func seed() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        for _ in 0..<min(430,Int(bounds.width*bounds.height/11500*density)) {
            flakes.append(flake(x:.random(in:0...bounds.width),y:.random(in:0...bounds.height)))
        }
    }

    func setShelves(_ shelves: [Shelf], screen: CGRect) {
        var old = Dictionary(uniqueKeysWithValues:drifts.map { ($0.shelf.id,$0) })
        drifts = shelves.compactMap { s in
            var local = s
            local.left = max(0,s.left-screen.minX)
            local.right = min(bounds.width,s.right-screen.minX)
            local.y -= screen.minY
            guard local.right-local.left > 6, local.y >= 0, local.y <= bounds.height+2 else { return nil }
            if let d = old.removeValue(forKey:s.id) { d.update(local); return d }
            let d = Drift(local)
            field.insertSublayer(d.shape, at:0)
            return d
        }.sorted { $0.shelf.y < $1.shelf.y }
        dockSnow = drifts.filter { $0.shelf.id.hasPrefix("d") }
        for gone in old.values { gone.shape.removeFromSuperlayer() }
    }

    func advance(dt: CGFloat, mouse: CGPoint, held: Bool, tilt: CGFloat, impulse: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        time += dt
        let previous = previousMouse ?? mouse
        previousMouse = mouse
        let dx = mouse.x-previous.x, dy = mouse.y-previous.y
        let distance = hypot(dx,dy)
        let moving = distance > 0.6 && distance < 500
        func closest(_ x:CGFloat,_ y:CGFloat) -> CGPoint {
            let t = min(1,max(0,((x-previous.x)*dx+(y-previous.y)*dy)/max(0.01,distance*distance)))
            return CGPoint(x:previous.x+t*dx,y:previous.y+t*dy)
        }
        motionCooldown -= dt
        let shake = impulse > 0.077 && motionCooldown <= 0
        if shake { motionCooldown = 0.22 }
        if moving || shake {
            for drift in drifts {
                let s = drift.shelf
                if !shake && (s.y < min(previous.y,mouse.y)-38 || s.y > max(previous.y,mouse.y)+38 ||
                    s.right < min(previous.x,mouse.x)-42 || s.left > max(previous.x,mouse.x)+42) { continue }
                for i in drift.depths.indices where drift.depths[i] > 0.45 {
                    let x = min(s.right,s.left+CGFloat(i)*Drift.step)
                    let p = closest(x,s.y)
                    let swept = moving && hypot(x-p.x,s.y-p.y) < 35
                    if swept || (shake && CGFloat.random(in:0...1) < min(0.6,impulse)) {
                        let lost = min(drift.depths[i],swept ? 3.8 : 2.4)
                        drift.depths[i] -= lost
                        drift.changed = true
                        if flakes.count < 750 && CGFloat.random(in:0...1) < min(1,lost*0.60) {
                            var f = flake(x:x,y:s.y-drift.depths[i]-3)
                            f.style = Int.random(in:0...2); f.size = .random(in:2.5...5)
                            f.vx = (swept ? min(230,max(-230,dx/dt*0.35)) : tilt*170) + .random(in:-34...34)
                            f.vy = -CGFloat.random(in:28...115)
                            flakes.append(f)
                        }
                    }
                }
            }
        }

        emission += dt * bounds.width / 95 * density
        while emission >= 1 {
            if flakes.count < 750 { flakes.append(flake(x:.random(in:0...bounds.width),y:-10)) }
            emission -= 1
        }
        var survivors = 0
        for i in flakes.indices {
            var f = flakes[i]
            let lastY = f.y
            let wind = sin(time*0.46 + f.phase)*14 + sin(time*0.19)*7 + tilt*205
            f.vx += (wind-f.vx)*min(1,dt*1.25)
            f.vy += (f.fall-f.vy)*min(1,dt*1.7)
            if moving {
                let p = closest(f.x,f.y)
                let sx = f.x-p.x, sy = f.y-p.y, radius = hypot(sx,sy)
                if radius < 84 {
                    let push = (1-radius/84)*min(1,distance/11)
                    f.vx += min(120,max(-120,dx/dt*0.13))*push + sx/max(1,radius)*push*52
                    f.vy += min(90,max(-90,dy/dt*0.10))*push + sy/max(1,radius)*push*42
                }
            }
            if shake { f.vx += CGFloat.random(in:-95...95)*min(1,impulse*2); f.vy -= min(1,impulse*3)*45 }
            f.x += f.vx*dt
            f.y += f.vy*dt
            if f.x < -12 { f.x = bounds.width+10 }
            if f.x > bounds.width+12 { f.x = -10 }
            var landed = false
            for drift in drifts {
                let s = drift.shelf
                if s.y < lastY-2 { continue }
                if s.y > f.y+11 { break }
                guard f.x >= s.left && f.x <= s.right else { continue }
                let j = drift.bin(f.x)
                let surface = s.y-drift.depths[j]
                if lastY <= surface && f.y >= surface && CGFloat.random(in:0...1) < (s.isWindow ? 0.72:0.90) {
                    drift.deposit(j,amount:f.size*0.15)
                    landed = true
                    break
                }
            }
            if !landed && f.y < bounds.height+12 {
                flakes[survivors] = f
                survivors += 1
            }
        }
        flakes.removeLast(flakes.count-survivors)
        render()
        santas.update(dt:dt,dockSnow:dockSnow)
        peekers.update(dt:dt,mouse:mouse,dragging:held && moving)
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for d in drifts where d.changed {
            let s = d.shelf, path = CGMutablePath()
            path.move(to:CGPoint(x:s.left,y:s.y))
            for (i,h) in d.depths.enumerated() {
                let x = min(s.right,s.left+CGFloat(i)*Drift.step)
                let taper = min(1,min(x-s.left,s.right-x)/6)
                path.addLine(to:CGPoint(x:x,y:s.y-h*max(0,taper)))
            }
            path.addLine(to:CGPoint(x:s.right,y:s.y)); path.closeSubpath()
            d.shape.path = path
            d.shape.shadowPath = path
            d.changed = false
        }
        while spriteLayers.count < flakes.count {
            let sprite = CALayer()
            field.addSublayer(sprite)
            spriteLayers.append(sprite)
            spriteStyles.append(-1)
        }
        for (i,f) in flakes.enumerated() {
            let sprite = spriteLayers[i]
            if spriteStyles[i] != f.style {
                sprite.contents = Self.sprites[f.style]
                spriteStyles[i] = f.style
            }
            if sprite.bounds.width != f.size {
                sprite.bounds = CGRect(x:0,y:0,width:f.size,height:f.size)
            }
            sprite.position = CGPoint(x:f.x,y:f.y)
            if sprite.isHidden { sprite.isHidden = false }
        }
        for i in flakes.count..<spriteLayers.count where !spriteLayers[i].isHidden {
            spriteLayers[i].isHidden = true
        }
    }
}
