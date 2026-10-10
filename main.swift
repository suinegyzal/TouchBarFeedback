// TouchBarFeedback — 터치바를 누를 때 트랙패드 햅틱/클릭 소리로 피드백을 준다.
import Cocoa
import AudioToolbox
import IOKit
import ServiceManagement
import UniformTypeIdentifiers

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

// 클릭 소리 종류. 소리 파일은 저장소에 넣지 않고 사용자 맥에 있는 파일을 읽는다.
enum SoundChoice: String { case todok, tink, custom }

final class Settings {
    private let d = UserDefaults.standard
    init() { d.register(defaults: ["haptic": true, "sound": true, "strength": Strength.medium.rawValue]) }
    var haptic: Bool { get { d.bool(forKey: "haptic") } set { d.set(newValue, forKey: "haptic") } }
    var sound: Bool { get { d.bool(forKey: "sound") } set { d.set(newValue, forKey: "sound") } }
    var soundChoice: SoundChoice {
        get { SoundChoice(rawValue: d.string(forKey: "soundChoice") ?? "") ?? .todok }
        set { d.set(newValue.rawValue, forKey: "soundChoice") }
    }
    var customSoundPath: String? { get { d.string(forKey: "customSoundPath") } set { d.set(newValue, forKey: "customSoundPath") } }
    var strength: Strength {
        get { Strength(rawValue: Int32(d.integer(forKey: "strength"))) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "strength") }
    }
}

// MARK: - 터치바 버튼 판별 (손쉬운 사용 API)

// 앱과 Control Strip이 터치바에 올린 요소는 AXFunctionRowTopLevelElements 로 읽을 수 있고,
// 그 좌표는 터치 위치(NSTouch.location)와 같은 터치바 좌표계(가로 약 1004pt)를 쓴다.
enum TouchBarLayout {
    private static let containerRoles: Set<String> = ["AXGroup", "AXList", "AXScrollArea", "AXSplitGroup", "AXLayoutArea", "AXFunctionRowTopLevelElement"]
    private static let passiveRoles: Set<String> = ["AXStaticText", "AXImage", "AXUnknown"]

    static func hasButton(atX x: CGFloat) -> Bool {
        var pids = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.apple.controlstrip" }.map(\.processIdentifier)
        if let front = NSWorkspace.shared.frontmostApplication { pids.append(front.processIdentifier) }
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            for top in elements(app, "AXFunctionRowTopLevelElements") where hit(top, x, depth: 0) { return true }
        }
        return false
    }

    private static func hit(_ e: AXUIElement, _ x: CGFloat, depth: Int) -> Bool {
        if depth > 0 {
            let f = frame(e)
            guard f.width > 0, x >= f.minX, x <= f.maxX else { return false }
            let role = string(e, kAXRoleAttribute) ?? ""
            if passiveRoles.contains(role) { return false }
            if !containerRoles.contains(role) { return true }
        }
        guard depth < 6 else { return false }
        return elements(e, kAXChildrenAttribute).contains { hit($0, x, depth: depth + 1) }
    }

    private static func value(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }
    private static func elements(_ e: AXUIElement, _ a: String) -> [AXUIElement] { value(e, a) as? [AXUIElement] ?? [] }
    private static func string(_ e: AXUIElement, _ a: String) -> String? { value(e, a) as? String }
    private static func frame(_ e: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let v = value(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if let v = value(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }
}

// MARK: - 앱

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = Settings()
    let haptic = Haptic()
    var statusItem: NSStatusItem!
    var tap: CFMachPort?
    var clickSounds: [SystemSoundID] = []
    var nextSound = 0
    var enabled = true

    func applicationDidFinishLaunching(_ note: Notification) {
        loadSound()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: L("터치바 피드백", "Touch Bar Feedback"))
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        startTap()

        // 첫 손쉬운 사용 조회는 느려서(약 0.1초), 시작할 때와 앱을 전환할 때 미리 한 번 조회해 둔다.
        warmUpLayout()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.warmUpLayout()
        }
    }

    func warmUpLayout() {
        guard AXIsProcessTrusted() else { return }
        _ = TouchBarLayout.hasButton(atX: -1)
    }

    // 현재 선택한 소리를 미리 로드해 둔다 (재생 지연을 줄이기 위해)
    func loadSound() {
        let path: String
        switch settings.soundChoice {
        case .custom: path = settings.customSoundPath ?? "/System/Library/Sounds/Tink.aiff"
        case .tink, .todok: path = "/System/Library/Sounds/Tink.aiff"
        }
        clickSounds.forEach { AudioServicesDisposeSystemSoundID($0) }
        let paths = settings.soundChoice == .todok
            ? (0..<3).compactMap { Bundle.main.path(forResource: "todok_\($0)", ofType: "wav") }
            : [path]
        clickSounds = paths.map { p in
            var id: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(URL(fileURLWithPath: p) as CFURL, &id)
            return id
        }
    }

    func playClick() {
        guard !clickSounds.isEmpty else { return }
        AudioServicesPlaySystemSound(clickSounds[nextSound % clickSounds.count])
        nextSound += 1
    }

    // 터치바 터치는 제스처 이벤트로 들어온다. 입력 모니터링 권한이 있어야 터치바 터치가 전달된다.
    func startTap() {
        dlog("startTap listen=\(CGPreflightListenEventAccess()) ax=\(AXIsProcessTrusted()) haptic=\(haptic.available)")
        // 손쉬운 사용 권한 하나로 터치 감지와 버튼 판별을 모두 할 수 있다.
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        let mask = (CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue))
                 | (CGEventMask(1) << CGEventMask(NSEvent.EventType.directTouch.rawValue))
        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            let app = Unmanaged<App>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = app.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if let ev = NSEvent(cgEvent: cgEvent),
                      ({ dlog("event touches=\(ev.allTouches().map { "dev\(App.isTouchBar($0) ? "TB" : "other")/ph\($0.phase.rawValue)/rest\($0.isResting)" })"); return true })(),
                      let touch = ev.allTouches().first(where: { $0.phase == .began && !$0.isResting && App.isTouchBar($0) }) {
                app.touchBegan(touch)
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

    func touchBegan(_ touch: NSTouch) {
        // 버튼이 아닌 곳(빈 곳, 버튼 사이)을 누르면 반응하지 않는다.
        if AXIsProcessTrusted(), touch.type == .direct {
            let x = touch.location(in: nil).x
            let onButton = TouchBarLayout.hasButton(atX: x)
            dlog("touch x=\(x) onButton=\(onButton)")
            guard onButton else { return }
        }
        feedback()
    }

    func feedback() {
        guard enabled else { return }
        if settings.haptic { haptic.fire(settings.strength.rawValue) }
        if settings.sound { playClick() }
    }

    // MARK: 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AXIsProcessTrusted() {
            menu.addItem(item(L("⚠️ 손쉬운 사용 권한 필요 — 여기서 열기", "⚠️ Accessibility permission needed — open"), #selector(openPrivacy)))
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
        menu.addItem(item(L("    토독", "    Todok"), #selector(chooseTodok), on: settings.soundChoice == .todok))
        let tink = item("    Tink", #selector(chooseTink), on: settings.soundChoice == .tink)
        menu.addItem(tink)
        let customTitle = settings.customSoundPath.map { (L("    파일: ", "    File: ") + ($0 as NSString).lastPathComponent) }
        menu.addItem(item(customTitle ?? L("    파일 선택…", "    Choose file…"), #selector(chooseCustom), on: settings.soundChoice == .custom))
        if settings.customSoundPath != nil { menu.addItem(item(L("    다른 파일 선택…", "    Choose another file…"), #selector(pickFile))) }
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
    @objc func toggleSound() { settings.sound.toggle(); if settings.sound { playClick() } }
    func setSound(_ choice: SoundChoice) {
        settings.soundChoice = choice
        settings.sound = true
        loadSound()
        playClick()
    }
    @objc func chooseTodok() { setSound(.todok) }
    @objc func chooseTink() { setSound(.tink) }
    @objc func chooseCustom() { settings.customSoundPath == nil ? pickFile() : setSound(.custom) }
    @objc func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = L("터치바를 누를 때 재생할 소리 파일을 고르세요 (짧은 소리 권장)", "Choose a sound to play on each Touch Bar tap (short sounds work best)")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.customSoundPath = url.path
        setSound(.custom)
    }
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
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
