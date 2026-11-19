import Cocoa

/// Santas who pop up from behind the top edge of an open window, have a look around, and duck back down.
final class PeekingSantas {
    /// Sprite height at Small. Taller than the Dock walkers, since only the top half shows.
    static let height: CGFloat = 42
    /// Share of the sprite (hat, face and beard) that rises above the window edge.
    static let peek: CGFloat = 0.5
    /// Clear space a Santa needs above a window edge, including the bounce as it pops up.
    static func clearance(for size: SantaSize) -> CGFloat { ceil(height*size.scale*peek*1.12)+4 }
    /// Distance kept from the ends of an edge, clear of rounded corners and neighbouring windows.
    private static let margin: CGFloat = 20

    private enum Phase { case waiting, rising, watching, sinking }

    private final class Peeker {
        let clip = CALayer()
        let sprite = CALayer()
        var phase = Phase.waiting
        var clock: CGFloat          // Seconds left in the current phase.
        var span: CGFloat = 1       // Full length of the current phase.
        var window = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var direction: CGFloat = 1
        var from: CGFloat = 1       // How far up the Santa was when it started to sink.
        var rest: CGFloat = 0       // Pause after sinking before the next peek.
        var glanced = false
        var animation: CGFloat = 0
        var lastFrame = -1

        init(wait: CGFloat) { clock = wait }

        /// How far up the Santa is, from 0 (hidden) to 1 (peeking), with a little bounce on the way up.
        var rise: CGFloat {
            let t = min(1, max(0, 1-clock/span))
            switch phase {
            case .waiting: return 0
            case .rising:
                let u = t-1
                return 1+u*u*(2.7*u+1.7)
            case .watching: return 1
            case .sinking: return from*(1-t*t)
            }
        }

        func begin(_ next: Phase, for length: CGFloat) {
            phase = next
            span = max(0.01, length)
            clock = length
        }

        func sink(after rest: CGFloat, taking length: CGFloat) {
            from = rise
            self.rest = rest
            begin(.sinking, for:length)
        }
    }

    private let peekers = [Peeker(wait:.random(in:1.2...2.4)), Peeker(wait:.random(in:8...14))]
    private var lookouts: [Lookout] = []
    let container = CALayer()
    var enabled = true
    var size: SantaSize = .small

    init() {
        // Behind the drifts, so snow on the window edge stays in front of the Santa.
        container.zPosition = -1
        for p in peekers {
            p.clip.masksToBounds = true
            p.clip.isHidden = true
            p.sprite.magnificationFilter = .linear
            p.sprite.minificationFilter = .trilinear
            p.clip.addSublayer(p.sprite)
            container.addSublayer(p.clip)
        }
    }

    private var spriteSize: CGSize {
        let height = Self.height*size.scale
        guard let image = DockSantas.idle.first else { return CGSize(width:height*0.63, height:height) }
        return CGSize(width:height*CGFloat(image.width)/CGFloat(image.height), height:height)
    }

    func setLookouts(_ all: [Lookout], screen: CGRect) {
        let clearance = Self.clearance(for:size)
        lookouts = all.compactMap { l in
            var local = l
            local.left = max(0, l.left-screen.minX)
            local.right = min(screen.width, l.right-screen.minX)
            local.y -= screen.minY
            guard local.right-local.left > 40, local.y >= clearance, local.y <= screen.height else { return nil }
            return local
        }
        // A Santa whose window moved, closed, or slipped behind another one disappears with it.
        let half = spriteSize.width/2+4
        for p in peekers where p.phase != .waiting {
            let stillThere = lookouts.contains { $0.window == p.window && abs($0.y-p.y) < 0.5 && $0.left+half <= p.x && p.x <= $0.right-half }
            if !stillThere { p.begin(.waiting, for:.random(in:2...5)) }
        }
    }

    func update(dt: CGFloat, mouse: CGPoint, dragging: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard enabled, !DockSantas.idle.isEmpty else {
            container.isHidden = true
            for p in peekers where p.phase != .waiting { p.begin(.waiting, for:.random(in:1...3)) }
            return
        }
        container.isHidden = false
        let sprite = spriteSize
        let visible = sprite.height*Self.peek
        for p in peekers {
            p.clock -= dt
            if p.phase == .rising || p.phase == .watching {
                // Santas are shy: a cursor drawing near, or a window being dragged, sends them back down.
                let head = CGRect(x:p.x-sprite.width/2, y:p.y-visible*p.rise, width:sprite.width, height:visible*p.rise)
                if dragging || head.insetBy(dx:-50, dy:-50).contains(mouse) {
                    p.sink(after:.random(in:6...12), taking:0.16)
                }
            }
            switch p.phase {
            case .waiting:
                if dragging { p.clock = max(p.clock, 1.5) }
                // Check back soon while there's nowhere to peek, but leave a pause after another Santa.
                if p.clock <= 0 && !emerge(p, width:sprite.width, mouse:mouse) {
                    p.clock = lookouts.isEmpty ? 0.5 : .random(in:2.5...6)
                }
            case .rising:
                if p.clock <= 0 {
                    p.begin(.watching, for:.random(in:3.2...5.5))
                    p.glanced = false
                }
            case .watching:
                if !p.glanced && p.clock < p.span/2 {
                    p.glanced = true
                    if CGFloat.random(in:0...1) < 0.7 { p.direction *= -1 }
                }
                if p.clock <= 0 { p.sink(after:.random(in:4...11), taking:0.42) }
            case .sinking:
                if p.clock <= 0 { p.begin(.waiting, for:p.rest) }
            }
            draw(p, sprite:sprite, visible:visible, dt:dt)
        }
    }

    private func emerge(_ p: Peeker, width: CGFloat, mouse: CGPoint) -> Bool {
        let busy = Set(peekers.filter { $0 !== p && $0.phase != .waiting }.map(\.window))
        let reach = width/2+Self.margin
        let spots = lookouts.filter { !busy.contains($0.window) && $0.right-$0.left >= 2*reach }
        guard let spot = spots.randomElement() else { return false }
        let x = CGFloat.random(in:spot.left+reach...spot.right-reach)
        // Never pop up right under the cursor.
        guard hypot(x-mouse.x, spot.y-mouse.y) > 140 else { return false }
        p.window = spot.window
        p.x = x
        p.y = spot.y
        p.direction = Bool.random() ? 1 : -1
        p.animation = .random(in:0...16)
        p.begin(.rising, for:0.5)
        return true
    }

    private func draw(_ p: Peeker, sprite: CGSize, visible: CGFloat, dt: CGFloat) {
        guard p.phase != .waiting else {
            if !p.clip.isHidden { p.clip.isHidden = true }
            return
        }
        p.animation += dt*8
        let frame = Int(p.animation) % DockSantas.idle.count
        if p.lastFrame != frame {
            p.sprite.contents = DockSantas.idle[frame]
            p.lastFrame = frame
        }
        // The clip's lower edge is the window's top edge, so the Santa rises from behind the window.
        p.clip.frame = CGRect(x:p.x-sprite.width/2-2, y:p.y-sprite.height, width:sprite.width+4, height:sprite.height)
        p.sprite.bounds = CGRect(origin:.zero, size:sprite)
        p.sprite.position = CGPoint(x:sprite.width/2+2, y:sprite.height*1.5-visible*p.rise)
        p.sprite.transform = CATransform3DMakeScale(p.direction, 1, 1)
        p.clip.isHidden = false
    }
}
