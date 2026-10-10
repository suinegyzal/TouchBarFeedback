// TouchBarFeedback — 터치바를 누를 때 트랙패드 햅틱/클릭 소리로 피드백을 준다.
import Cocoa
import AudioToolbox
import IOKit
import ServiceManagement

// MARK: - 트랙패드 햅틱 (MultitouchSupport 비공개 프레임워크)

final class Haptic {
    private typealias CreateFn = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias OpenFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ActuateFn = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32

    private var actuator: UnsafeMutableRawPointer?
    private var create: CreateFn?
    private var openFn: OpenFn?
    private var actuate: ActuateFn?

    init() {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let c = dlsym(lib, "MTActuatorCreateFromDeviceID"),
              let o = dlsym(lib, "MTActuatorOpen"),
              let a = dlsym(lib, "MTActuatorActuate") else { return }
        create = unsafeBitCast(c, to: CreateFn.self)
        openFn = unsafeBitCast(o, to: OpenFn.self)
        actuate = unsafeBitCast(a, to: ActuateFn.self)
        open()
    }

    private func open() {
        guard let create, let openFn else { return }
        for id in Haptic.actuatableDeviceIDs() {
            if let act = create(id), openFn(act) == 0 { actuator = act; break }
        }
    }

    var available: Bool { actuator != nil }

    func fire(_ pattern: Int32) {
        guard let act = actuator, let actuate else { return }
        let r = actuate(act, pattern, 0, 0, 0)
        dlog("actuate pattern=\(pattern) result=\(r)")
        if r != 0 { actuator = nil; open(); if let act = actuator { _ = actuate(act, pattern, 0, 0, 0) } }
    }

    private static func actuatableDeviceIDs() -> [UInt64] {
        var ids: [UInt64] = []
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iter) == KERN_SUCCESS else { return ids }
        defer { IOObjectRelease(iter) }
        while case let dev = IOIteratorNext(iter), dev != 0 {
            defer { IOObjectRelease(dev) }
            let supported = IORegistryEntryCreateCFProperty(dev, "ActuationSupported" as CFString, nil, 0)?.takeRetainedValue() as? Bool ?? false
            if supported, let id = IORegistryEntryCreateCFProperty(dev, "Multitouch ID" as CFString, nil, 0)?.takeRetainedValue() as? NSNumber {
                ids.append(id.uint64Value)
            }
        }
        return ids
    }
}

// MARK: - 문자열 (시스템 언어가 한국어면 한국어, 아니면 영어)

let isKorean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
func L(_ ko: String, _ en: String) -> String { isKorean ? ko : en }

// `defaults write local.touchbarfeedback debug -bool true` 이면 ~/Library/Logs/TouchBarFeedback.log 에 기록
func dlog(_ m: @autoclosure () -> String) {
    guard UserDefaults.standard.bool(forKey: "debug") else { return }
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/TouchBarFeedback.log")
    let line = "\(Date()) \(m())\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

// MARK: - 설정

enum Strength: Int32, CaseIterable {
    case weak = 3, medium = 4, strong = 6
    var title: String { switch self { case .weak: L("약하게", "Light"); case .medium: L("보통", "Medium"); case .strong: L("강하게", "Strong") } }
}

final class Settings {
    private let d = UserDefaults.standard
    init() { d.register(defaults: ["haptic": true, "sound": false, "strength": Strength.medium.rawValue]) }
    var haptic: Bool { get { d.bool(forKey: "haptic") } set { d.set(newValue, forKey: "haptic") } }
    var sound: Bool { get { d.bool(forKey: "sound") } set { d.set(newValue, forKey: "sound") } }
    var strength: Strength {
        get { Strength(rawValue: Int32(d.integer(forKey: "strength"))) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "strength") }
    }
}

// MARK: - 앱

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = Settings()
    let haptic = Haptic()
    var statusItem: NSStatusItem!
    var tap: CFMachPort?
    var clickSound: SystemSoundID = 0
    var enabled = true

    func applicationDidFinishLaunching(_ note: Notification) {
        AudioServicesCreateSystemSoundID(URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff") as CFURL, &clickSound)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: L("터치바 피드백", "Touch Bar Feedback"))
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        startTap()
    }

    // 터치바 터치는 제스처 이벤트 중 direct 타입 터치로 들어온다.
    // 입력 모니터링 권한이 없으면 탭은 만들어져도 이벤트가 오지 않으므로, 권한이 생길 때까지 기다렸다가 만든다.
    func startTap() {
        let trusted = CGPreflightListenEventAccess() || AXIsProcessTrusted()
        dlog("startTap listen=\(CGPreflightListenEventAccess()) ax=\(AXIsProcessTrusted()) haptic=\(haptic.available)")
        if !trusted { CGRequestListenEventAccess() }
        let mask = (CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue))
                 | (CGEventMask(1) << CGEventMask(NSEvent.EventType.directTouch.rawValue))
        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            let app = Unmanaged<App>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = app.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if let ev = NSEvent(cgEvent: cgEvent),
                      ({ dlog("event touches=\(ev.allTouches().map { "dev\(App.isTouchBar($0) ? "TB" : "other")/ph\($0.phase.rawValue)/rest\($0.isResting)" })"); return true })(),
                      ev.allTouches().contains(where: { $0.phase == .began && !$0.isResting && App.isTouchBar($0) }) {
                app.feedback()
            }
            return Unmanaged.passUnretained(cgEvent)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        dlog("tapCreate=\(tap != nil)")
        if let tap {
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startTap() }
        }
    }

    // 터치바 터치인지는 NSTouch의 비공개 속성 device.deviceType(3 = 터치바)으로 구분한다.
    // (터치바 터치도 type이 .direct로 오지 않는 경우가 있어 type으로는 구분할 수 없다)
    static func isTouchBar(_ touch: NSTouch) -> Bool {
        guard touch.responds(to: NSSelectorFromString("device")),
              let device = touch.value(forKey: "device") as? NSObject,
              device.responds(to: NSSelectorFromString("deviceType")) else { return touch.type == .direct }
        return (device.value(forKey: "deviceType") as? Int) == 3
    }

    func feedback() {
        guard enabled else { return }
        if settings.haptic { haptic.fire(settings.strength.rawValue) }
        if settings.sound { AudioServicesPlaySystemSound(clickSound) }
    }

    // MARK: 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !(CGPreflightListenEventAccess() || AXIsProcessTrusted()) {
            menu.addItem(item(L("⚠️ 입력 모니터링 권한 필요 — 여기서 열기", "⚠️ Input Monitoring permission needed — open"), #selector(openPrivacy)))
            menu.addItem(.separator())
        }
        if !haptic.available { menu.addItem(withTitle: L("⚠️ 햅틱 트랙패드를 찾지 못함", "⚠️ No haptic trackpad found"), action: nil, keyEquivalent: "") }

        menu.addItem(item(L("켜기", "Enabled"), #selector(toggleEnabled), on: enabled))
        menu.addItem(.separator())
        menu.addItem(item(L("햅틱", "Haptic"), #selector(toggleHaptic), on: settings.haptic))
        for s in Strength.allCases {
            let i = item("    \(s.title)", #selector(setStrength(_:)), on: settings.strength == s)
            i.tag = Int(s.rawValue)
            menu.addItem(i)
        }
        menu.addItem(item(L("클릭 소리", "Click sound"), #selector(toggleSound), on: settings.sound))
        menu.addItem(.separator())
        menu.addItem(item(L("로그인 시 자동 실행", "Launch at login"), #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(item(L("종료", "Quit"), #selector(NSApplication.terminate(_:)), key: "q"))
    }

    func item(_ title: String, _ action: Selector, on: Bool = false, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        i.state = on ? .on : .off
        return i
    }

    @objc func toggleEnabled() { enabled.toggle() }
    @objc func toggleHaptic() { settings.haptic.toggle() }
    @objc func toggleSound() { settings.sound.toggle(); if settings.sound { AudioServicesPlaySystemSound(clickSound) } }
    @objc func setStrength(_ sender: NSMenuItem) {
        settings.strength = Strength(rawValue: Int32(sender.tag)) ?? .medium
        haptic.fire(settings.strength.rawValue)
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
    @objc func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
