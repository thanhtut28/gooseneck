import AppKit
import SwiftUI

/// Manages the lifecycle and positioning of the Dynamic Island overlay window.
@Observable
final class PostureIslandManager {

    private var window: PostureIslandWindow?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var revealWorkItem: DispatchWorkItem?

    private(set) var notchWidth: CGFloat = 185
    private(set) var notchHeight: CGFloat = 38
    private(set) var hasNotch: Bool = false

    /// Published so the island view can react to visibility changes.
    var isRevealed: Bool = true

    func show(viewModel: PostureViewModel) {
        guard window == nil else {
            if let window {
                positionOnScreen(window)
            }
            window?.orderFrontRegardless()
            return
        }

        detectNotch()

        let windowWidth = notchWidth + 180
        let windowHeight: CGFloat = 240

        let panel = PostureIslandWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        let hostingView = NSHostingView(
            rootView: PostureIslandView(
                notchWidth: notchWidth,
                notchHeight: notchHeight,
                hasNotch: hasNotch
            ).environment(viewModel)
        )
        // Prevent the hosting view from auto-resizing the window when
        // the SwiftUI content changes size (expand / collapse / nudge).
        // Without this, the resize triggers a constraint update mid-display-cycle
        // and AppKit throws an exception (SIGABRT in _postWindowNeedsUpdateConstraints).
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        window = panel
        positionOnScreen(panel)
        panel.alphaValue = 0
        isRevealed = false
        panel.orderFrontRegardless()

        // Initial reveal — emerge from notch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.revealFromNotch()
        }

        // Screen parameter changes (display config, resolution)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.detectNotch()
            if let window = self?.window { self?.positionOnScreen(window) }
        }

        // Space / desktop transition completed.
        // With .moveToActiveSpace the window slides away with the departing
        // desktop during the transition. When this notification fires the
        // system has already moved the window to the new space — we just
        // need to reveal it smoothly.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceChange()
        }
    }

    func updateShadow(radius: CGFloat, opacity: Float, offsetY: CGFloat) {
        // Shadow is now rendered via SwiftUI .shadow() on the clipped view
        // so it correctly follows the pill shape instead of the rectangular window.
    }

    func hide() {
        revealWorkItem?.cancel()
        revealWorkItem = nil

        window?.orderOut(nil)
        window = nil

        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
    }

    // MARK: - Space Transition

    /// Called after a space change completes. The window was moved to the
    /// new space by the system (`.moveToActiveSpace`). We hide it immediately
    /// (preventing a flash) and then smoothly reveal it from the notch.
    private func handleSpaceChange() {
        guard let window else { return }

        // Cancel any pending reveal to debounce rapid space switches
        revealWorkItem?.cancel()

        // Instantly make invisible on the new space
        window.alphaValue = 0
        isRevealed = false

        // Reposition in case the main screen changed
        positionOnScreen(window)
        window.orderFrontRegardless()

        // Wait for the transition to fully settle before re-emerging
        let workItem = DispatchWorkItem { [weak self] in
            self?.revealFromNotch()
        }
        revealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    /// Animate the island emerging from the notch.
    private func revealFromNotch() {
        guard let window else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().alphaValue = 1.0
        }

        // Slightly delayed so the SwiftUI morph animates after the window fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.isRevealed = true
        }
    }

    // MARK: - Notch Detection

    private func detectNotch() {
        guard let screen = preferredScreen() else {
            hasNotch = false
            notchWidth = 185
            notchHeight = 38
            return
        }

        hasNotch = screen.safeAreaInsets.top > 0
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
            notchHeight = screen.safeAreaInsets.top
        } else {
            notchWidth = 185
            notchHeight = 38
        }
    }

    private func positionOnScreen(_ window: NSWindow) {
        guard let screen = preferredScreen() else { return }
        let screenFrame = screen.frame
        let windowWidth = notchWidth + 180
        let windowHeight: CGFloat = 240

        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.maxY - windowHeight
        window.setFrame(
            NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            display: false
        )
    }

    private func preferredScreen() -> NSScreen? {
        if let windowScreen = window?.screen,
           windowScreen.safeAreaInsets.top > 0 {
            return windowScreen
        }

        if let builtInNotchedScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return builtInNotchedScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}
