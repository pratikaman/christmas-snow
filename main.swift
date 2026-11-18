import Cocoa
import OSLog

private final class Overlay: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SnowApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let motion = MacMotion()
    private let menu = NSMenu()
    private var status: NSStatusItem!
    private var scenes: [(window:Overlay,view:SnowView,display:DisplayArea)] = []
    private var timer: Timer?
    private var paused = false
    private var asleep = false
    private var previousTime = 0.0
    private var nextLayout = 0.0
    private var pendingLayout = false
    private var generation = 0
    private var layout = Layout()
    private var density = CGFloat(UserDefaults.standard.double(forKey:"density"))
    private let layoutQueue = DispatchQueue(label:"local.christmassnow.geometry",qos:.utility)
    private let logger = Logger(subsystem:"local.christmassnow",category:"overlay")
    private var showSantas = UserDefaults.standard.object(forKey:"showSantas") as? Bool ?? true
    private var santaSize = UserDefaults.standard.string(forKey:"santaSize").flatMap(SantaSize.init(rawValue:)) ?? .small
    private var reported = false

    func applicationDidFinishLaunching(_ notification:Notification) {
        if ![0.55,1,1.8].contains(density) { density = 1 }
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName:"snowflake",accessibilityDescription:"Christmas Snow")
        status.button?.toolTip = "Christmas Snow"
        status.menu = menu
        menu.delegate = self
        rebuildMenu()
        NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self,selector:#selector(suspend),name:NSWorkspace.screensDidSleepNotification,object:nil)
        center.addObserver(self,selector:#selector(resume),name:NSWorkspace.screensDidWakeNotification,object:nil)
        center.addObserver(self,selector:#selector(spaceChanged),name:NSWorkspace.activeSpaceDidChangeNotification,object:nil)
        screensChanged()
        synchronize()
    }
    @objc private func screensChanged() {
        generation += 1
        scenes.forEach { $0.window.orderOut(nil) }
        scenes.removeAll()
        guard let primary = NSScreen.screens.first else { return }
        func quartz(_ rect:CGRect) -> CGRect {
            CGRect(x:rect.minX,y:primary.frame.maxY-rect.maxY,width:rect.width,height:rect.height)
        }
        for screen in NSScreen.screens {
            let r = screen.frame
            let window = Overlay(contentRect:r,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.setFrame(r,display:false)
            window.isFloatingPanel = true
            window.level = NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1)
            window.hidesOnDeactivate = false
            window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = false; window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            window.animationBehavior = .none
            let view = SnowView(frame:CGRect(origin:.zero,size:r.size))
            window.contentView = view
            view.santas.size = santaSize
            view.density = density; view.santas.enabled = showSantas; view.seed()
            scenes.append((window,view,DisplayArea(frame:quartz(r),work:quartz(screen.visibleFrame))))
            if !paused && !asleep { window.orderFrontRegardless() }
        }
        nextLayout = 0
    }
    @objc private func spaceChanged() { nextLayout = 0 }
    @objc private func suspend() { asleep = true; synchronize() }
    @objc private func resume() { asleep = false; screensChanged(); synchronize() }

    private func synchronize() {
        timer?.invalidate(); timer = nil
        if paused || asleep {
            motion.stop()
            scenes.forEach { $0.window.orderOut(nil) }
            return
        }
        scenes.forEach { $0.window.orderFrontRegardless() }
        motion.start()
        previousTime = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.004
        RunLoop.main.add(t,forMode:.common); timer = t
        nextLayout = 0
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0.001,min(0.065,now-previousTime)); previousTime = now
        let cursor = NSEvent.mouseLocation
        let mouse = CGPoint(x:cursor.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-cursor.y)
        let impulse = motion.takeImpulse()
        for (_,view,display) in scenes {
            view.advance(dt:dt,mouse:CGPoint(x:mouse.x-display.frame.minX,y:mouse.y-display.frame.minY),tilt:motion.tilt,impulse:impulse)
        }
        if now >= nextLayout && !pendingLayout {
            nextLayout = now+0.65
            pendingLayout = true
            let displays = scenes.map(\.display)
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.dock").first?.processIdentifier
            let revision = generation
            layoutQueue.async { [weak self] in
                let result = readLayout(displays:displays,foreground:pid,dockPID:dock,mouse:mouse)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pendingLayout = false
                    guard self.generation == revision else { return }
                    self.layout = result
                    for (_,view,d) in self.scenes {
                        view.setShelves(result.shelves,screen:d.frame)
                        view.santas.route = result.routes.compactMap { $0.local(to:d.frame) }.first
                    }
                }
            }
        }
        if !reported && !layout.shelves.isEmpty && motion.samples > 20 {
            reported = true
            logger.notice("Snowfall running: \(self.scenes.count) displays, \(self.scenes.first?.view.flakes.count ?? 0) flakes, \(self.layout.shelves.count) edges, \(self.layout.tabs) tabs, \(self.layout.dockIcons) Dock icons, \(self.motion.samples) motion samples")
        }
    }
    func menuWillOpen(_ menu:NSMenu) { rebuildMenu() }
    @discardableResult
    private func item(_ title:String,_ action:Selector?,in targetMenu:NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title:title,action:action,keyEquivalent:"")
        entry.target = self
        targetMenu.addItem(entry)
        return entry
    }
    private func rebuildMenu() {
        menu.removeAllItems()
        item(paused ? "Resume Snowfall" : "Pause Snowfall",#selector(togglePause),in:menu)
        let snow = item("Snowfall Intensity",nil,in:menu)
        let amounts = NSMenu()
        for (i,pair) in ["Light","Classic","Snowstorm"].enumerated() {
            let option = item(pair,#selector(changeDensity(_:)),in:amounts)
            option.tag = i
            option.state = density == [0.55,1,1.8][i] ? .on:.off
        }
        snow.submenu = amounts
        item("Roaming Santas",#selector(toggleSantas),in:menu).state = showSantas ? .on:.off
        let sizes = NSMenu()
        for size in SantaSize.allCases {
            let option = item(size.rawValue,#selector(changeSantaSize(_:)),in:sizes)
            option.representedObject = size.rawValue
            option.state = size == santaSize ? .on : .off
        }
        item("Santa Size",nil,in:menu).submenu = sizes
        menu.addItem(.separator())
        let sensor = paused ? "Mac motion paused" : motion.active ? "Mac motion active" : motion.samples > 0 ? "Waiting for Mac motion" : motion.detail
        item(sensor,nil,in:menu)
        if motion.active { item("Set Current Tilt as Level",#selector(recenter),in:menu) }
        if !AXIsProcessTrusted() { item("Enable Precise Tab and Dock Edges…",#selector(requestEdges),in:menu) }
        menu.addItem(.separator())
        item("Quit Christmas Snow",#selector(quit),in:menu).keyEquivalent = "q"
    }
    @objc private func togglePause() { paused.toggle(); synchronize() }
    @objc private func toggleSantas() {
        showSantas.toggle()
        UserDefaults.standard.set(showSantas,forKey:"showSantas")
        for scene in scenes { scene.view.santas.enabled = showSantas }
    }
    @objc private func recenter() { motion.calibrate() }
    @objc private func changeSantaSize(_ sender:NSMenuItem) {
        guard let value = sender.representedObject as? String, let size = SantaSize(rawValue:value) else { return }
        santaSize = size
        UserDefaults.standard.set(value,forKey:"santaSize")
        for scene in scenes { scene.view.santas.size = size }
    }
    @objc private func changeDensity(_ sender:NSMenuItem) {
        density = [0.55,1.0,1.8][sender.tag]
        UserDefaults.standard.set(Double(density),forKey:"density")
        scenes.forEach { $0.view.density = density }
    }
    @objc private func requestEdges() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt:true] as CFDictionary)
        nextLayout = 0
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) { timer?.invalidate(); motion.stop() }
}

let app = NSApplication.shared
let delegate = SnowApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
