import AppKit
import Darwin
import Foundation

private let bridgeURL = URL(string: ProcessInfo.processInfo.environment["PEEKDOCK_BRIDGE_URL"] ?? "http://127.0.0.1:4173")!
private let repoRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PEEKDOCK_ROOT"] ?? FileManager.default.currentDirectoryPath)
private let lockURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("peekdock-overlay.lock")
private let agents = ["codex", "claude", "jimeng", "browser"]
private let overlayBaseSize = NSSize(width: 210, height: 390)
private let overlayWidthToHeight: CGFloat = 7.0 / 13.0
private let overlayMinimumWidth: CGFloat = 140
private let overlayMaximumWidth: CGFloat = 420
private let overlayWidthDefaultsKey = "PeekDockOverlayPortraitWidth"

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
    case "needs_input": return "APPROVAL"
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
    private let progressLabel = NSTextField(labelWithString: "")
    private let statusDot = DotView()
    private let progressView = ProgressView()
    private lazy var approvalButton: NSButton = {
        let button = NSButton(title: "允许并继续", target: self, action: #selector(acceptApproval))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = color(for: "codex").cgColor
        button.layer?.cornerRadius = 10
        button.contentTintColor = .black
        button.font = .systemFont(ofSize: 11, weight: .bold)
        button.isHidden = true
        return button
    }()
    private let resizeGrip = NSTextField(labelWithString: "◢")
    private var currentState: BridgeState?
    private var selectedAgent = "codex"
    private var alternateFrame = false
    private var animationTimer: Timer?
    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    private var resizeStartFrame: NSRect?
    private var horizontalScrollAccumulator: CGFloat = 0
    private var lastSwipeAt: TimeInterval = 0
    private var approvalWasVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.043, blue: 0.058, alpha: 0.96).cgColor
        layer?.cornerRadius = 24
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.13).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.42
        layer?.shadowRadius = 22
        layer?.shadowOffset = NSSize(width: 0, height: -8)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true

        configure(agentLabel, frame: NSRect(x: 22, y: 352, width: 110, height: 18), size: 12, weight: .bold, color: .white)
        configure(targetLabel, frame: NSRect(x: 22, y: 334, width: 160, height: 12), size: 8, weight: .medium, color: NSColor(calibratedWhite: 0.5, alpha: 1))
        targetLabel.stringValue = "REAL AGENTS · DESKTOP"
        statusDot.frame = NSRect(x: 177, y: 355, width: 10, height: 10)
        statusDot.wantsLayer = true

        imageView.frame = NSRect(x: 35, y: 205, width: 140, height: 140)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        configure(primaryLabel, frame: NSRect(x: 18, y: 165, width: 174, height: 28), size: 18, weight: .bold, color: .white)
        primaryLabel.alignment = .center
        configure(detailLabel, frame: NSRect(x: 22, y: 137, width: 166, height: 26), size: 10, weight: .regular, color: NSColor(calibratedWhite: 0.72, alpha: 1))
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 2
        configure(titleLabel, frame: NSRect(x: 24, y: 110, width: 162, height: 16), size: 9, weight: .medium, color: NSColor(calibratedWhite: 0.88, alpha: 1))
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        configure(progressLabel, frame: NSRect(x: 25, y: 82, width: 160, height: 18), size: 12, weight: .bold, color: .white)
        progressLabel.alignment = .center
        progressView.frame = NSRect(x: 28, y: 68, width: 154, height: 6)
        configure(dotsLabel, frame: NSRect(x: 39, y: 29, width: 132, height: 18), size: 9, weight: .regular, color: NSColor(calibratedWhite: 0.45, alpha: 1))
        dotsLabel.alignment = .center
        approvalButton.frame = NSRect(x: 28, y: 63, width: 154, height: 34)
        configure(resizeGrip, frame: NSRect(x: 188, y: 7, width: 14, height: 14), size: 10, weight: .regular, color: NSColor(calibratedWhite: 0.42, alpha: 1))
        resizeGrip.alignment = .center

        [agentLabel, targetLabel, statusDot, imageView, primaryLabel, detailLabel, titleLabel, progressLabel, progressView, dotsLabel, resizeGrip, approvalButton].forEach(addSubview)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.48, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.alternateFrame.toggle()
            self.render()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let scale = min(bounds.width / overlayBaseSize.width, bounds.height / overlayBaseSize.height)
        let xOffset = (bounds.width - overlayBaseSize.width * scale) / 2
        let yOffset = (bounds.height - overlayBaseSize.height * scale) / 2
        func scaled(_ rect: NSRect) -> NSRect {
            NSRect(
                x: xOffset + rect.origin.x * scale,
                y: yOffset + rect.origin.y * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }

        agentLabel.frame = scaled(NSRect(x: 22, y: 352, width: 110, height: 18))
        targetLabel.frame = scaled(NSRect(x: 22, y: 334, width: 160, height: 12))
        statusDot.frame = scaled(NSRect(x: 177, y: 355, width: 10, height: 10))
        imageView.frame = scaled(NSRect(x: 35, y: 205, width: 140, height: 140))
        primaryLabel.frame = scaled(NSRect(x: 18, y: 165, width: 174, height: 28))
        detailLabel.frame = scaled(NSRect(x: 22, y: 137, width: 166, height: 26))
        titleLabel.frame = scaled(NSRect(x: 24, y: 110, width: 162, height: 16))
        progressLabel.frame = scaled(NSRect(x: 25, y: 82, width: 160, height: 18))
        progressView.frame = scaled(NSRect(x: 28, y: 68, width: 154, height: 6))
        dotsLabel.frame = scaled(NSRect(x: 39, y: 29, width: 132, height: 18))
        approvalButton.frame = scaled(NSRect(x: 28, y: 63, width: 154, height: 34))
        resizeGrip.frame = scaled(NSRect(x: 188, y: 7, width: 14, height: 14))

        agentLabel.font = .systemFont(ofSize: 12 * scale, weight: .bold)
        targetLabel.font = .systemFont(ofSize: 8 * scale, weight: .medium)
        primaryLabel.font = .systemFont(ofSize: 18 * scale, weight: .bold)
        detailLabel.font = .systemFont(ofSize: 10 * scale, weight: .regular)
        titleLabel.font = .systemFont(ofSize: 9 * scale, weight: .medium)
        progressLabel.font = .systemFont(ofSize: 12 * scale, weight: .bold)
        dotsLabel.font = .systemFont(ofSize: 9 * scale, weight: .regular)
        approvalButton.font = .systemFont(ofSize: 11 * scale, weight: .bold)
        approvalButton.layer?.cornerRadius = 10 * scale
        resizeGrip.font = .systemFont(ofSize: 10 * scale, weight: .regular)
        layer?.cornerRadius = 24 * scale
        layer?.shadowRadius = 22 * scale
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let gripSize = max(24, bounds.width * 0.075)
        addCursorRect(NSRect(x: bounds.maxX - gripSize, y: bounds.minY, width: gripSize, height: gripSize), cursor: .resizeLeftRight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !approvalButton.isHidden && approvalButton.frame.contains(point) { return approvalButton }
        return self
    }

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
        let approvalAgent = agents.first(where: { state.tasks[$0]?.status == "needs_input" })
        if let approvalAgent {
            if !approvalWasVisible { selectedAgent = approvalAgent }
        } else if let selectedTask = state.tasks[selectedAgent], selectedTask.status == "idle",
           let focusedTask = state.tasks[state.currentAgent], focusedTask.status != "idle" {
            selectedAgent = state.currentAgent
        }
        approvalWasVisible = approvalAgent != nil
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
            : status == "needs_input" && selectedAgent == "codex"
                ? (task?.statusText.localizedCaseInsensitiveContains("accessibility") == true
                    ? "Enable ChatGPT in Accessibility"
                    : "Codex is waiting for permission")
                : (task?.statusText.isEmpty == false ? task!.statusText : "Waiting for real activity")
        titleLabel.stringValue = task?.title ?? "PeekDock"
        progressView.progress = max(0, task?.progress ?? 0)
        progressView.accent = accent
        let hasProgress = (task?.progress ?? -1) >= 0 && status != "needs_input"
        progressLabel.stringValue = hasProgress ? "\(max(0, task?.progress ?? 0))%" : ""
        progressLabel.isHidden = !hasProgress
        progressView.isHidden = status == "needs_input"
        approvalButton.isHidden = !(selectedAgent == "codex" && status == "needs_input")
        approvalButton.layer?.backgroundColor = accent.cgColor
        statusDot.dotColor = disconnected ? (health?.state == "error" ? .systemRed : .systemOrange) : accent
        statusDot.glowing = status == "running" || status == "needs_input"
        let activeIndex = agents.firstIndex(of: selectedAgent) ?? 0
        dotsLabel.stringValue = agents.indices.map { $0 == activeIndex ? "●" : "○" }.joined(separator: "  ")
    }

    private func selectAgent(_ agent: String) {
        guard agents.contains(agent) else { return }
        selectedAgent = agent
        render()
        var request = URLRequest(url: bridgeURL.appendingPathComponent("api/switch-agent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["agent": selectedAgent])
        URLSession.shared.dataTask(with: request).resume()
    }

    private func switchAgent(_ direction: Int) {
        let index = agents.firstIndex(of: selectedAgent) ?? 0
        selectAgent(agents[(index + direction + agents.count) % agents.count])
    }

    private func sendAgentAction(_ action: String) {
        var request = URLRequest(url: bridgeURL.appendingPathComponent("api/agent-action"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["agent": selectedAgent, "action": action])
        URLSession.shared.dataTask(with: request).resume()
    }

    private func activeApplication(for agent: String) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        switch agent {
        case "codex":
            return NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first(where: \.isActive)
        case "claude":
            return running.first(where: { $0.localizedName == "Trae CN" && $0.isActive })
        case "jimeng", "browser":
            return running.first(where: {
                ($0.bundleIdentifier == "com.google.Chrome" || $0.bundleIdentifier == "com.apple.Safari") && $0.isActive
            })
        default:
            return nil
        }
    }

    private func toggleSelectedAgentApplication() {
        if let application = activeApplication(for: selectedAgent) {
            application.hide()
            return
        }
        sendAgentAction("open_agent")
    }

    @objc private func acceptApproval() {
        approvalButton.title = "正在允许…"
        approvalButton.isEnabled = false
        sendAgentAction("accept_confirmation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.approvalButton.title = "允许并继续"
            self?.approvalButton.isEnabled = true
        }
    }

    override func swipe(with event: NSEvent) {
        guard abs(event.deltaX) > abs(event.deltaY), abs(event.deltaX) > 0.1 else { return }
        switchAgent(event.deltaX > 0 ? -1 : 1)
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontal = event.scrollingDeltaX
        guard abs(horizontal) > abs(event.scrollingDeltaY) else {
            horizontalScrollAccumulator = 0
            return
        }
        horizontalScrollAccumulator += horizontal
        let now = Date.timeIntervalSinceReferenceDate
        if abs(horizontalScrollAccumulator) >= 28 && now - lastSwipeAt > 0.32 {
            switchAgent(horizontalScrollAccumulator > 0 ? -1 : 1)
            horizontalScrollAccumulator = 0
            lastSwipeAt = now
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            horizontalScrollAccumulator = 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        let point = convert(event.locationInWindow, from: nil)
        let gripSize = max(24, bounds.width * 0.075)
        if point.x >= bounds.maxX - gripSize && point.y <= bounds.minY + gripSize {
            resizeStartFrame = window?.frame
            windowOrigin = nil
            return
        }
        resizeStartFrame = nil
        windowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let window else { return }
        let current = NSEvent.mouseLocation
        if let start = resizeStartFrame {
            let horizontalDelta = current.x - dragOrigin.x
            let verticalDelta = dragOrigin.y - current.y
            let horizontalWidth = start.width + horizontalDelta
            let verticalWidth = (start.height + verticalDelta) * overlayWidthToHeight
            let proposedWidth = abs(horizontalDelta) >= abs(verticalDelta) ? horizontalWidth : verticalWidth
            let width = min(overlayMaximumWidth, max(overlayMinimumWidth, proposedWidth))
            let height = width / overlayWidthToHeight
            let frame = NSRect(x: start.minX, y: start.maxY - height, width: width, height: height)
            window.setFrame(frame, display: true)
            return
        }
        guard let windowOrigin else { return }
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + current.x - dragOrigin.x, y: windowOrigin.y + current.y - dragOrigin.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragOrigin else { return }
        if resizeStartFrame != nil {
            if let width = window?.frame.width {
                UserDefaults.standard.set(Double(width), forKey: overlayWidthDefaultsKey)
            }
            self.dragOrigin = nil
            self.resizeStartFrame = nil
            return
        }
        let current = NSEvent.mouseLocation
        let moved = abs(current.x - dragOrigin.x) + abs(current.y - dragOrigin.y)
        let clickPoint = convert(event.locationInWindow, from: nil)
        self.dragOrigin = nil
        self.windowOrigin = nil
        guard moved < 6 else { return }
        if dotsLabel.frame.insetBy(dx: -8, dy: -6).contains(clickPoint) {
            let relativeX = min(dotsLabel.bounds.width - 0.1, max(0, clickPoint.x - dotsLabel.frame.minX))
            let index = min(agents.count - 1, Int(relativeX / dotsLabel.frame.width * CGFloat(agents.count)))
            selectAgent(agents[index])
            return
        }
        toggleSelectedAgentApplication()
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
        let savedWidth = CGFloat(UserDefaults.standard.double(forKey: overlayWidthDefaultsKey))
        let width = savedWidth > 0 ? min(overlayMaximumWidth, max(overlayMinimumWidth, savedWidth)) : overlayBaseSize.width
        let size = NSSize(width: width, height: width / overlayWidthToHeight)
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentAspectRatio = NSSize(width: 7, height: 13)
        panel.contentMinSize = NSSize(width: overlayMinimumWidth, height: overlayMinimumWidth / overlayWidthToHeight)
        panel.contentMaxSize = NSSize(width: overlayMaximumWidth, height: overlayMaximumWidth / overlayWidthToHeight)
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
