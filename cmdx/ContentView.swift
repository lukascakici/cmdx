import SwiftUI
import ApplicationServices
import Combine

class EventInterceptor: ObservableObject {
    static let shared = EventInterceptor()
    
    @Published var isTrusted = false
    private var isCutPending = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Key codes
    private let kVK_ANSI_X: CGKeyCode = 0x07
    private let kVK_ANSI_V: CGKeyCode = 0x09
    private let kVK_ANSI_C: CGKeyCode = 0x08
    
    func checkPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func start() {
        checkPermissions()
        guard isTrusted else { return }
        
        // Listen for BOTH key down and key up
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
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }
    
    private var xIsCutPending = false
    private var vIsCutPending = false
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passRetained(event) }
        
        // Check if frontmost app is Finder
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" {
            return Unmanaged.passRetained(event)
        }
        
        let flags = event.flags
        let isCmdPressed = flags.contains(.maskCommand)
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Command+X OR releasing X after Command+X
        if (isCmdPressed && keyCode == kVK_ANSI_X) || (keyCode == kVK_ANSI_X && xIsCutPending) {
            if type == .keyDown {
                isCutPending = true
                xIsCutPending = true
            } else if type == .keyUp {
                xIsCutPending = false
            }
            
            // Mutate in-place to C
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_C))
            return Unmanaged.passRetained(event)
        }
        
        // Command+V OR releasing V
        if (isCmdPressed && keyCode == kVK_ANSI_V) || (keyCode == kVK_ANSI_V && vIsCutPending) {
            if isCutPending || vIsCutPending {
                if type == .keyDown {
                    vIsCutPending = true
                    
                    let source = CGEventSource(stateID: .privateState)
                    let loc = CGEventTapLocation.cghidEventTap
                    
                    // 1. Post Option Down
                    let optDown = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: true)
                    optDown?.flags = [.maskCommand, .maskAlternate]
                    optDown?.post(tap: loc)
                    
                    // 2. Post V Down (with Option+Cmd flag)
                    let vDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true)
                    vDown?.flags = [.maskCommand, .maskAlternate]
                    vDown?.post(tap: loc)
                    
                    // 3. Post V Up
                    let vUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false)
                    vUp?.flags = [.maskCommand, .maskAlternate]
                    vUp?.post(tap: loc)
                    
                    // 4. Post Option Up
                    let optUp = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: false)
                    optUp?.flags = .maskCommand
                    optUp?.post(tap: loc)
                    
                    isCutPending = false
                    
                    // Clear the pasteboard after a 0.5s delay to prevent pasting again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSPasteboard.general.clearContents()
                    }
                } else if type == .keyUp {
                    vIsCutPending = false
                }
                
                // Swallow completely -> we generated our own full key sequence for V!
                return nil
            }
        }
        
        // Standard Cmd+C cancels pending cut
        if isCmdPressed && keyCode == kVK_ANSI_C && type == .keyDown {
            isCutPending = false
            xIsCutPending = false
            vIsCutPending = false
        }
        
        return Unmanaged.passRetained(event)
    }
}

struct ContentView: View {
    @StateObject private var interceptor = EventInterceptor.shared
    
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "scissors")
                .imageScale(.large)
                .foregroundColor(.accentColor)
                .font(.system(size: 32))
            
            Text("cmdx")
                .font(.headline)
            
            Divider()
            
            if interceptor.isTrusted {
                Text("✅ Active")
                    .foregroundColor(.green)
                    .fontWeight(.bold)
                Text("Ready! Use Cmd+X to cut files in Finder.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("⚠️ Access Required")
                    .foregroundColor(.red)
                    .fontWeight(.bold)
                
                Text("Please grant accessibility permissions to detect keystrokes.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 10) {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    
                    Button("Check Again") {
                        interceptor.checkPermissions()
                        if interceptor.isTrusted {
                            interceptor.start()
                        }
                    }
                }
                .padding(.top, 5)
            }
            
            Spacer()
            
            Divider()
            
            Button("Quit cmdx") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .padding(.bottom, 5)
        }
        .padding()
        .frame(width: 260, height: interceptor.isTrusted ? 260 : 350)
        .onAppear {
            interceptor.start()
        }
    }
}

#Preview {
    ContentView()
}
