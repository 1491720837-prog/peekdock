import AppKit
import Darwin
import Foundation

private let bridgeURL = URL(string: ProcessInfo.processInfo.environment["PEEKDOCK_BRIDGE_URL"] ?? "http://127.0.0.1:4173")!
private let repoRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PEEKDOCK_ROOT"] ?? FileManager.default.currentDirectoryPath)
private let lockURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("peekdock-overlay.lock")
private let agents = ["codex", "claude", "jimeng", "browser"]

private struct AgentTask {
    let source: String
    let title: String
    let status: String
    let statusText: String
    let progress: Int
}

private struct AdapterHealth {
    let state: String
    let detail: String
}

private struct BridgeState {
    let currentAgent: String
    let tasks: [String: AgentTask]
    let health: [String: AdapterHealth]
    let displayTarget: String
}

private func color(for agent: String) -> NSColor {
    switch agent {
    case "claude": return NSColor(calibratedRed: 0.95, green: 0.61, blue: 0.32, alpha: 1)
    case "jimeng": return NSColor(calibratedRed: 0.66, green: 0.46, blue: 1, alpha: 1)
    case "browser": return NSColor(calibratedRed: 0.38, green: 0.72, blue: 1, alpha: 1)
    default: return NSColor(calibratedRed: 0.41, green: 0.78, blue: 0.43, alpha: 1)
    }
}

private func displayName(for agent: String) -> String {
    switch agent {
    case "claude": return "CLAUDE"
    case "jimeng": return "JIMENG"
    case "browser": return "BROWSER"
    default: return "CODEX"
    }
}

private func statusName(_ status: String) -> String {
    switch status {
    case "running": return "WORKING"
    case "needs_input": return "NEED INPUT"
    case "completed": return "DONE"
    case "failed": return "ERROR"
    default: return "IDLE"
    }
}

private func assetURL(agent: String, status: String, alternate: Bool) -> URL {
    let suffix = alternate ? "_b" : ""
    let root = repoRoot.appendingPathComponent("assets")
    if agent == "browser" {
        return root.appendingPathComponent("raw/browser_working_\(alternate ? "02" : "01").png")
    }
    let normalizedStatus: String
    if status == "completed" {
        normalizedStatus = "completed"
    } else if status == "running" {
        normalizedStatus = "running"
    } else if (status == "failed" || status == "needs_input") && agent == "codex" {
        normalizedStatus = "error"
    } else if status == "failed" || status == "needs_input" {
        normalizedStatus = "completed"
    } else {
        normalizedStatus = "idle"
    }
    return root.appendingPathComponent("processed/p2_\(agent)/\(agent)_\(normalizedStatus)_p2\(suffix).png")
}

private final class ProgressView: NSView {
    var progress = 0 { didSet { needsDisplay = true } }
    var accent = NSColor.systemGreen { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        guard progress > 0 else { return }
        let width = max(5, bounds.width * CGFloat(min(100, progress)) / 100)
        accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: 3, yRadius: 3).fill()
    }
}

private final class DotView: NSView {
    var dotColor = NSColor.systemGray { didSet { needsDisplay = true } }
    var glowing = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        if glowing {
            layer?.shadowColor = dotColor.cgColor
            layer?.shadowOpacity = 0.8
            layer?.shadowRadius = 5
            layer?.shadowOffset = .zero
        } else {
            layer?.shadowOpacity = 0
        }
        dotColor.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}

private final class OverlayView: NSView {
    private let imageView = NSImageView()
    private let agentLabel = NSTextField(labelWithString: "CODEX")
    private let primaryLabel = NSTextField(labelWithString: "IDLE")
    private let detailLabel = NSTextField(wrappingLabelWithString: "Connecting to real agents…")
    private let titleLabel = NSTextField(labelWithString: "PeekDock")
    private let targetLabel = NSTextField(labelWithString: "DESKTOP OVERLAY")
    private let dotsLabel = NSTextField(labelWithString: "●  ○  ○  ○")
    private let statusDot = DotView()
    private let progressView = ProgressView()
    private var currentState: BridgeState?
    private var selectedAgent = "codex"
    private var alternateFrame = false
    private var animationTimer: Timer?
    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.043, blue: 0.058, alpha: 0.96).cgColor
        layer?.cornerRadius = 28
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.13).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.42
        layer?.shadowRadius = 22
        layer?.shadowOffset = NSSize(width: 0, height: -8)

        configure(agentLabel, frame: NSRect(x: 18, y: 276, width: 100, height: 16), size: 11, weight: .bold, color: .white)
        configure(targetLabel, frame: NSRect(x: 18, y: 258, width: 130, height: 12), size: 8, weight: .medium, color: NSColor(calibratedWhite: 0.5, alpha: 1))
        targetLabel.stringValue = "REAL AGENTS · DESKTOP"
        statusDot.frame = NSRect(x: 158, y: 278, width: 9, height: 9)
        statusDot.wantsLayer = true

        imageView.frame = NSRect(x: 35, y: 128, width: 120, height: 120)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        configure(primaryLabel, frame: NSRect(x: 18, y: 101, width: 154, height: 21), size: 15, weight: .bold, color: .white)
        primaryLabel.alignment = .center
        configure(detailLabel, frame: NSRect(x: 20, y: 70, width: 150, height: 30), size: 9, weight: .regular, color: NSColor(calibratedWhite: 0.72, alpha: 1))
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 2
        configure(titleLabel, frame: NSRect(x: 22, y: 49, width: 146, height: 15), size: 9, weight: .medium, color: NSColor(calibratedWhite: 0.88, alpha: 1))
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        progressView.frame = NSRect(x: 24, y: 36, width: 142, height: 5)
        configure(dotsLabel, frame: NSRect(x: 20, y: 13, width: 150, height: 14), size: 8, weight: .regular, color: NSColor(calibratedWhite: 0.45, alpha: 1))
        dotsLabel.alignment = .center

        [agentLabel, targetLabel, statusDot, imageView, primaryLabel, detailLabel, titleLabel, progressView, dotsLabel].forEach(addSubview)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.48, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.alternateFrame.toggle()
            self.render()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ label: NSTextField, frame: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        label.frame = frame
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
    }

    func apply(_ state: BridgeState) {
        currentState = state
        if selectedAgent.isEmpty || !agents.contains(selectedAgent) { selectedAgent = state.currentAgent }
        if let selectedTask = state.tasks[selectedAgent], selectedTask.status == "idle",
           let focusedTask = state.tasks[state.currentAgent], focusedTask.status != "idle" {
            selectedAgent = state.currentAgent
        }
        render()
    }

    private func render() {
        guard let state = currentState else { return }
        let task = state.tasks[selectedAgent]
        let health = state.health[selectedAgent]
        let status = task?.status ?? "idle"
        let accent = color(for: selectedAgent)
        agentLabel.stringValue = displayName(for: selectedAgent)
        agentLabel.textColor = accent
        targetLabel.stringValue = state.displayTarget == "hardware" ? "REAL AGENTS · USB DOCK" : "REAL AGENTS · DESKTOP"
        imageView.image = NSImage(contentsOf: assetURL(agent: selectedAgent, status: status, alternate: alternateFrame))

        let disconnected = health != nil && health?.state != "connected"
        primaryLabel.stringValue = disconnected && status == "idle" ? health!.state.uppercased() : statusName(status)
        detailLabel.stringValue = disconnected && status == "idle"
            ? health!.detail
            : (task?.statusText.isEmpty == false ? task!.statusText : "Waiting for real activity")
        titleLabel.stringValue = task?.title ?? "PeekDock"
        progressView.progress = max(0, task?.progress ?? 0)
        progressView.accent = accent
        statusDot.dotColor = disconnected ? (health?.state == "error" ? .systemRed : .systemOrange) : accent
        statusDot.glowing = status == "running" || status == "needs_input"
        let activeIndex = agents.firstIndex(of: selectedAgent) ?? 0
        dotsLabel.stringValue = agents.indices.map { $0 == activeIndex ? "●" : "○" }.joined(separator: "  ")
    }

    private func switchAgent(_ direction: Int) {
        let index = agents.firstIndex(of: selectedAgent) ?? 0
        selectedAgent = agents[(index + direction + agents.count) % agents.count]
        render()
        var request = URLRequest(url: bridgeURL.appendingPathComponent("api/switch-agent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["agent": selectedAgent])
        URLSession.shared.dataTask(with: request).resume()
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let windowOrigin, let window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + current.x - dragOrigin.x, y: windowOrigin.y + current.y - dragOrigin.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragOrigin else { return }
        let current = NSEvent.mouseLocation
        let moved = abs(current.x - dragOrigin.x) + abs(current.y - dragOrigin.y)
        self.dragOrigin = nil
        self.windowOrigin = nil
        if moved < 6 { switchAgent(event.locationInWindow.x < bounds.midX ? -1 : 1) }
    }

    override func rightMouseUp(with event: NSEvent) {
        NSWorkspace.shared.open(bridgeURL)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var overlayView: OverlayView?
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        acquireSingleInstanceLock()
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        pollState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in self?.pollState() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        try? FileManager.default.removeItem(at: lockURL)
    }

    private func acquireSingleInstanceLock() {
        if let raw = try? String(contentsOf: lockURL, encoding: .utf8),
           let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)), kill(pid, 0) == 0 {
            _ = kill(pid, SIGTERM)
            usleep(180_000)
        }
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: lockURL, atomically: true, encoding: .utf8)
    }

    private func createPanel() {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 190, height: 310)
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        let view = OverlayView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        self.overlayView = view
    }

    private func pollState() {
        URLSession.shared.dataTask(with: bridgeURL.appendingPathComponent("api/state")) { [weak self] data, _, _ in
            guard let data, let state = Self.parse(data) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.overlayView?.apply(state)
                if state.displayTarget == "hardware" {
                    self.panel?.orderOut(nil)
                } else {
                    self.panel?.orderFrontRegardless()
                }
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> BridgeState? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawState = root["state"] as? [String: Any] else { return nil }
        var tasks: [String: AgentTask] = [:]
        if let rawTasks = rawState["tasksByAgent"] as? [String: Any] {
            for agent in agents {
                guard let raw = rawTasks[agent] as? [String: Any] else { continue }
                tasks[agent] = AgentTask(
                    source: raw["source"] as? String ?? agent,
                    title: raw["title"] as? String ?? displayName(for: agent),
                    status: raw["status"] as? String ?? "idle",
                    statusText: raw["statusText"] as? String ?? "",
                    progress: raw["progress"] as? Int ?? -1
                )
            }
        }
        var health: [String: AdapterHealth] = [:]
        if let rawHealth = rawState["adapterHealth"] as? [String: Any] {
            for agent in agents {
                guard let raw = rawHealth[agent] as? [String: Any] else { continue }
                health[agent] = AdapterHealth(state: raw["state"] as? String ?? "waiting", detail: raw["detail"] as? String ?? "")
            }
        }
        return BridgeState(
            currentAgent: rawState["currentAgent"] as? String ?? "codex",
            tasks: tasks,
            health: health,
            displayTarget: rawState["displayTarget"] as? String ?? "desktop-overlay"
        )
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
