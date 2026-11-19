import Cocoa

struct Shelf {
    let id: String
    var left: CGFloat
    var right: CGFloat
    var y: CGFloat
    let isWindow: Bool
}

struct DisplayArea {
    let frame: CGRect
    let work: CGRect
    /// The part of the top of the screen that hides anything the overlay draws beneath it.
    var blind: CGRect = .null
}

/// A stretch of a window's top edge with clear sky above it, where a Santa can peek out.
struct Lookout {
    let window: Int
    var left: CGFloat
    var right: CGFloat
    var y: CGFloat
}

struct Layout {
    var shelves: [Shelf] = []
    var lookouts: [Lookout] = []
    var routes: [DockRoute] = []
    var tabs = 0
    var dockIcons = 0
    var accessibility = false
}

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
private func frame(_ element: AXUIElement) -> CGRect? {
    guard let p = attribute(element, "AXPosition"), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = attribute(element, "AXSize"), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
          AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
private func children(_ e: AXUIElement) -> [AXUIElement] { attribute(e, "AXChildren") as? [AXUIElement] ?? [] }

private func focusedTabs(_ pid: pid_t) -> (CGRect, [CGRect])? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.06)
    guard let value = attribute(app, "AXFocusedWindow"),
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    let window = value as! AXUIElement
    guard let bounds = frame(window) else { return nil }
    var queue = [(window, false, 0)]
    var index = 0
    var tabs: [CGRect] = []
    let deadline = ProcessInfo.processInfo.systemUptime + 0.24
    while index < queue.count && index < 180 && ProcessInfo.processInfo.systemUptime < deadline {
        let (e, inGroup, depth) = queue[index]
        index += 1
        let role = attribute(e, "AXRole") as? String ?? ""
        if role == "AXTab" || (inGroup && ["AXRadioButton","AXButton"].contains(role)) ||
            (role == "AXRadioButton" && attribute(e, "AXSubrole") as? String == "AXTabButton") {
            if let r = frame(e), r.width >= 18, r.height >= 9, r.height < 75,
               bounds.intersects(r), r.minY < bounds.minY + 168 { tabs.append(r) }
            continue
        }
        if role == "AXTabGroup", let members = attribute(e, "AXTabs") as? [AXUIElement], !members.isEmpty {
            tabs += members.compactMap(frame).filter { $0.width >= 18 && $0.height < 75 && bounds.intersects($0) && $0.minY < bounds.minY + 168 }
            continue
        }
        if depth >= 10 || ["AXWebArea","AXHTMLArea","AXTextArea","AXTextField","AXList","AXOutline","AXTable","AXMenu","AXStaticText","AXImage","AXButton"].contains(role) { continue }
        for child in children(e).prefix(75) { queue.append((child, inGroup || role == "AXTabGroup", depth+1)) }
    }
    return (bounds, tabs)
}

private func visibleParts(of shelf: Shelf, behind covers: [CGRect], above: CGFloat = 2) -> [Shelf] {
    var segments = [shelf.left...shelf.right]
    for rect in covers where rect.minY < shelf.y + 1 && rect.maxY > shelf.y - above {
        segments = segments.flatMap { segment -> [ClosedRange<CGFloat>] in
            let a = segment.lowerBound, b = segment.upperBound
            guard a < rect.maxX && b > rect.minX else { return [segment] }
            var parts: [ClosedRange<CGFloat>] = []
            if rect.minX - a > 8 { parts.append(a...rect.minX) }
            if b - rect.maxX > 8 { parts.append(rect.maxX...b) }
            return parts
        }
    }
    return segments.enumerated().map { i,s in
        Shelf(id: "\(shelf.id).\(i)", left: s.lowerBound, right: s.upperBound, y: shelf.y, isWindow: shelf.isWindow)
    }
}

func readLayout(displays: [DisplayArea], foreground: pid_t?, dockPID: pid_t?, mouse: CGPoint, clearance: CGFloat) -> Layout {
    let trusted = AXIsProcessTrusted()
    let tabInfo = trusted ? foreground.flatMap(focusedTabs) : nil
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []
    var result = Layout(accessibility: trusted)
    var covers: [CGRect] = []
    // A Santa rising behind an opaque menu bar or the camera notch would never be seen.
    let blinds = displays.map(\.blind).filter { !$0.isNull }
    for item in info {
        guard (item[kCGWindowLayer as String] as? Int) == 0,
              (item[kCGWindowAlpha as String] as? Double ?? 1) > 0.2,
              let id = item[kCGWindowNumber as String] as? Int,
              let dict = item[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: dict), r.width > 36, r.height > 24 else { continue }
        var tabs: [CGRect] = []
        if let (focused, frames) = tabInfo, (item[kCGWindowOwnerPID as String] as? Int32) == foreground,
           abs(focused.minX-r.minX) < 5, abs(focused.minY-r.minY) < 5, abs(focused.width-r.width) < 6 {
            tabs = frames.sorted { $0.minX < $1.minX }
        }
        for (i,t) in tabs.enumerated() {
            let inset = min(12,t.width*0.10)
            let shelf = Shelf(id:"t\(id)-\(i)", left:t.minX+inset, right:t.maxX-inset, y:t.minY+min(8,t.height*0.2), isWindow:false)
            result.shelves += visibleParts(of:shelf, behind:covers)
            result.tabs += 1
        }
        // Leave the tab strip open to falling snow when individual tabs are available.
        let touchesMenu = displays.contains { abs($0.work.minY-r.minY) < 2 && $0.frame.intersects(r) }
        let top = Shelf(id:"w\(id)", left:r.minX+5, right:r.maxX-5, y:r.minY+(touchesMenu ? 7 : 2), isWindow:true)
        let columnMasks = tabs.map { CGRect(x:$0.minX, y:r.minY-8, width:$0.width, height:24) }
        result.shelves += visibleParts(of:top, behind:covers+columnMasks)
        // Santas peek from the real top edge, wherever nothing in front hides the space above it.
        if r.width >= 120 && r.height >= 60 {
            let edge = Shelf(id:"p\(id)", left:r.minX, right:r.maxX, y:r.minY, isWindow:true)
            result.lookouts += visibleParts(of:edge, behind:covers+blinds, above:clearance).map {
                Lookout(window:id, left:$0.left, right:$0.right, y:$0.y)
            }
        }
        covers.append(r)
    }
    var dockFrames: [CGRect] = []
    if trusted, let pid = dockPID {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.06)
        if let list = children(app).first {
            dockFrames = children(list).compactMap { e in
                guard attribute(e, "AXSubrole") as? String != "AXSeparatorDockItem" else { return nil }
                return frame(e)
            }
        }
    }
    let prefs = UserDefaults.standard.persistentDomain(forName:"com.apple.dock") ?? [:]
    let side = prefs["orientation"] as? String ?? "bottom"
    for (i,display) in displays.enumerated() {
        let r = display.frame, w = display.work
        let inset = side == "left" ? w.minX-r.minX : side == "right" ? r.maxX-w.maxX : r.maxY-w.maxY
        let items = dockFrames.filter { r.intersection($0).width > 8 && r.intersection($0).height > 8 }
        let hover = items.contains { $0.insetBy(dx:-4,dy:-4).contains(mouse) }
        let fullscreen = covers.contains { $0.contains(r.insetBy(dx:1,dy:1)) }
        guard (inset > 3 && !fullscreen) || hover else { continue }
        var dockRect: CGRect
        if !items.isEmpty {
            dockRect = items.reduce(CGRect.null) { $0.union($1) }
            for (n,b) in items.enumerated() where b.width >= 9 {
                let trim = min(b.width * 0.18, 9)
                result.shelves.append(Shelf(id:"d\(i).\(n)", left:b.minX+trim, right:b.maxX-trim, y:b.minY+3, isWindow:false))
            }
            result.dockIcons += items.count
        } else if inset > 3 {
            // A reserved Dock edge and item count provide a fallback without AX access.
            let tile = CGFloat(prefs["tilesize"] as? Double ?? 48)
            let count = ["persistent-apps","persistent-others","recent-apps"].reduce(2) { $0 + (prefs[$1] as? [Any] ?? []).count }
            let bottom = side == "bottom"
            let extent = min((bottom ? r.width : r.height) - 12, CGFloat(count)*min(tile+3,inset*0.66)+14)
            let x = bottom ? r.midX-extent/2 : side == "left" ? r.minX+3 : w.maxX+3
            dockRect = CGRect(x:x,y:bottom ? w.maxY+3 : r.midY-extent/2,width:bottom ? extent:max(8,inset-6),height:bottom ? inset:extent)
            result.shelves.append(Shelf(id:"dock\(i)",left:dockRect.minX,right:dockRect.maxX,y:dockRect.minY,isWindow:false))
        } else { continue }
        if side == "bottom" {
            result.routes.append(DockRoute(start:CGPoint(x:dockRect.minX+10,y:dockRect.minY),end:CGPoint(x:dockRect.maxX-10,y:dockRect.minY)))
        } else {
            let rail = side == "left" ? dockRect.maxX : dockRect.minX
            result.routes.append(DockRoute(start:CGPoint(x:rail,y:dockRect.minY+20),end:CGPoint(x:rail,y:dockRect.maxY-8)))
        }
    }
    return result
}
