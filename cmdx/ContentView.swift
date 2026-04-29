import AppKit
import ApplicationServices

final class EventInterceptor {
    static let shared = EventInterceptor()

    private(set) var isTrusted = false
    private var isCutPending = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Key codes
    private let kVK_ANSI_X: CGKeyCode = 0x07
    private let kVK_ANSI_V: CGKeyCode = 0x09
    private let kVK_ANSI_C: CGKeyCode = 0x08
    
    // Magic value to tag synthetic events we generate
    private let syntheticEventTag: Int64 = 0xC3DEC3DE
    
    private var activeAppBundleID: String = ""
    private var workspaceObserver: Any?
    private var permissionTimer: Timer?
    
    init() {
        activeAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.activeAppBundleID = app.bundleIdentifier ?? ""
            }
        }
    }
    
    deinit {
        stopPermissionMonitor()
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    func checkPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func start() {
        checkPermissions()
        guard isTrusted else { return }
        
        // Clean up any existing tap first
        stop()
        
        // Listen for key down, key up, and flags changed
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let mySelf = Unmanaged<EventInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return mySelf.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: pointer
        ) else {
            print("Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        // Start monitoring for permission revocation
        startPermissionMonitor()
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                runLoopSource = nil
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        // Reset all state
        isCutPending = false
        xIsCutPending = false
        vIsCutPending = false
    }
    
    /// Call on app termination to clear stale cut files from pasteboard
    func cleanup() {
        if cutPasteboardChangeCount >= 0 && NSPasteboard.general.changeCount == cutPasteboardChangeCount {
            NSPasteboard.general.clearContents()
        }
        cutPasteboardChangeCount = -1
    }
    
    // MARK: - Permission Monitoring
    
    private func startPermissionMonitor() {
        permissionTimer?.invalidate()
        // 5s instead of 2s — permission state changes are user-initiated and rare,
        // so polling less often saves wakeups across long uptime sessions.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = AXIsProcessTrusted()
            if !trusted && self.isTrusted {
                DispatchQueue.main.async {
                    self.isTrusted = false
                    self.stop()
                }
            } else if trusted && !self.isTrusted {
                DispatchQueue.main.async {
                    self.isTrusted = true
                    self.start()
                }
            }
        }
    }
    
    private func stopPermissionMonitor() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
    
    // MARK: - Event Handling
    
    private var xIsCutPending = false
    private var vIsCutPending = false
    private var cutPasteboardChangeCount: Int = -1
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it due to timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown || type == .keyUp else { return Unmanaged.passRetained(event) }

        // Fast path: 99% of system keystrokes happen outside Finder. Skip them
        // before touching any CGEvent properties or NSPasteboard, so the callback
        // does effectively zero allocation work for unrelated apps.
        if self.activeAppBundleID != "com.apple.finder" {
            return Unmanaged.passRetained(event)
        }

        // Drain any Cocoa autorelease objects (NSPasteboard, CFString bridges)
        // before the next keystroke so they don't accumulate over long uptime.
        return autoreleasepool { () -> Unmanaged<CGEvent>? in
            handleFinderEvent(type: type, event: event)
        }
    }

    private func handleFinderEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Skip our own synthetic events to prevent infinite loops
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventTag {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let isCmdPressed = flags.contains(.maskCommand)
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Standard Cmd+C — reset cut state
        if isCmdPressed && keyCode == kVK_ANSI_C && type == .keyDown {
            isCutPending = false
            xIsCutPending = false
            vIsCutPending = false
            return Unmanaged.passRetained(event)
        }
        
        // Command+X → rewrite to Cmd+C and mark cut pending
        if isCmdPressed && keyCode == kVK_ANSI_X {
            if type == .keyDown {
                isCutPending = true
                xIsCutPending = true
            } else if type == .keyUp {
                xIsCutPending = false
            }
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_C))
            return Unmanaged.passRetained(event)
        }
        
        // Handle X key-up when Cmd was already released (from the Cmd+X press)
        if keyCode == kVK_ANSI_X && xIsCutPending && type == .keyUp {
            xIsCutPending = false
            return nil // Swallow the stale X key-up, don't send C
        }
        
        // Command+V with cut pending → send Cmd+Option+V (move) instead
        if keyCode == kVK_ANSI_V {
            if isCmdPressed && isCutPending && type == .keyDown {
                // Consume the cut — one-time only
                isCutPending = false
                vIsCutPending = true
                cutPasteboardChangeCount = NSPasteboard.general.changeCount
                
                let source = CGEventSource(stateID: .privateState)
                source?.userData = syntheticEventTag
                let loc = CGEventTapLocation.cghidEventTap
                
                // Option down
                let optDown = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: true)
                optDown?.flags = [.maskCommand, .maskAlternate]
                optDown?.post(tap: loc)
                
                usleep(1000) // 1ms delay for Finder to register modifier
                
                // V down
                let vDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true)
                vDown?.flags = [.maskCommand, .maskAlternate]
                vDown?.post(tap: loc)
                
                usleep(1000)
                
                // V up
                let vUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false)
                vUp?.flags = [.maskCommand, .maskAlternate]
                vUp?.post(tap: loc)
                
                usleep(1000)
                
                // Option up
                let optUp = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: false)
                optUp?.flags = .maskCommand
                optUp?.post(tap: loc)
                
                return nil // Swallow original Cmd+V
            }
            
            // Block second Cmd+V if pasteboard still has the cut files
            if isCmdPressed && !isCutPending && type == .keyDown 
                && cutPasteboardChangeCount >= 0 
                && NSPasteboard.general.changeCount == cutPasteboardChangeCount {
                return nil // Prevent duplicate paste of cut files
            }
            
            // Swallow duplicate V events from the synthetic burst
            if isCmdPressed && vIsCutPending && type == .keyDown {
                return nil
            }
            
            if vIsCutPending && type == .keyUp {
                vIsCutPending = false
                return nil
            }
        }
        
        return Unmanaged.passRetained(event)
    }
}

