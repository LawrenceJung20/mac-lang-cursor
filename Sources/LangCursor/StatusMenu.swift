import AppKit
import LangCursorCore

/// The menu bar icon and its settings menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private static let inputMonitoringSettings = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    var onAlwaysOnChange: ((Bool) -> Void)?
    var onCatEnabledChange: ((Bool) -> Void)?
    var onCatSizeChange: ((CGFloat) -> Void)?
    var onHungerDelayChange: ((TimeInterval) -> Void)?
    var onPoopIntervalChange: ((TimeInterval) -> Void)?
    var keyboardAccessGranted: (() -> Bool)?

    var alwaysOn = false {
        didSet { alwaysOnItem.state = alwaysOn ? .on : .off }
    }
    var catEnabled = true {
        didSet { catEnabledItem.state = catEnabled ? .on : .off }
    }
    var catSize: CGFloat = 64 {
        didSet {
            for item in catSizeItems { item.state = CGFloat(item.tag) == catSize ? .on : .off }
        }
    }

    var hungerDelay: TimeInterval = 60 {
        didSet { Self.check(hungerItems, value: hungerDelay) }
    }
    var poopInterval: TimeInterval = 300 {
        didSet { Self.check(poopItems, value: poopInterval) }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let alwaysOnItem = NSMenuItem(
        title: "항상 켜져 있기",
        action: #selector(toggleAlwaysOn),
        keyEquivalent: ""
    )
    private let catEnabledItem = NSMenuItem(
        title: "바탕화면 고양이",
        action: #selector(toggleCat),
        keyEquivalent: ""
    )
    private var catSizeItems: [NSMenuItem] = []
    private var hungerItems: [NSMenuItem] = []
    private var poopItems: [NSMenuItem] = []
    private let permissionItem = NSMenuItem(
        title: "입력 모니터링 권한 허용…",
        action: #selector(openPermissionSettings),
        keyEquivalent: ""
    )

    override init() {
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        alwaysOnItem.target = self
        catEnabledItem.target = self
        catEnabledItem.state = .on
        permissionItem.target = self

        menu.addItem(catEnabledItem)
        let sizeItem = NSMenuItem(title: "고양이 크기", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (title, points) in [("아주 작게", 48), ("작게 (기본)", 64), ("보통", 80)] {
            let item = NSMenuItem(title: title, action: #selector(changeCatSize(_:)), keyEquivalent: "")
            item.tag = points
            item.target = self
            item.state = points == 64 ? .on : .off
            sizeMenu.addItem(item)
            catSizeItems.append(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        hungerItems = addChoiceMenu(
            to: menu, title: "배고파지는 시간",
            choices: [("30초", 30), ("1분 (기본)", 60), ("3분", 180), ("5분", 300), ("10분", 600), ("끄기", 0)],
            selected: hungerDelay, action: #selector(changeHungerDelay(_:))
        )
        poopItems = addChoiceMenu(
            to: menu, title: "똥 싸는 간격",
            choices: [("30초", 30), ("2분", 120), ("5분 (기본)", 300), ("10분", 600), ("끄기", 0)],
            selected: poopInterval, action: #selector(changePoopInterval(_:))
        )
        menu.addItem(.separator())
        menu.addItem(alwaysOnItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func show(_ language: InputLanguage) {
        statusItem.button?.title = language.label
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem.isHidden = keyboardAccessGranted?() ?? false
    }

    @objc private func toggleAlwaysOn() {
        alwaysOn.toggle()
        onAlwaysOnChange?(alwaysOn)
    }

    @objc private func toggleCat() {
        catEnabled.toggle()
        onCatEnabledChange?(catEnabled)
    }

    @objc private func changeCatSize(_ sender: NSMenuItem) {
        catSize = CGFloat(sender.tag)
        onCatSizeChange?(catSize)
    }

    @objc private func changeHungerDelay(_ sender: NSMenuItem) {
        hungerDelay = TimeInterval(sender.tag)
        onHungerDelayChange?(hungerDelay)
    }

    @objc private func changePoopInterval(_ sender: NSMenuItem) {
        poopInterval = TimeInterval(sender.tag)
        onPoopIntervalChange?(poopInterval)
    }

    /// A submenu of radio-style choices whose tags hold seconds.
    private func addChoiceMenu(
        to menu: NSMenu, title: String, choices: [(String, Int)],
        selected: TimeInterval, action: Selector
    ) -> [NSMenuItem] {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        var items: [NSMenuItem] = []
        for (label, seconds) in choices {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.tag = seconds
            item.target = self
            submenu.addItem(item)
            items.append(item)
        }
        Self.check(items, value: selected)
        parent.submenu = submenu
        menu.addItem(parent)
        return items
    }

    private static func check(_ items: [NSMenuItem], value: TimeInterval) {
        for item in items { item.state = TimeInterval(item.tag) == value ? .on : .off }
    }

    @objc private func openPermissionSettings() {
        NSWorkspace.shared.open(Self.inputMonitoringSettings)
    }
}
