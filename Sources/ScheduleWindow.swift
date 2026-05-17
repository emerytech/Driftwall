import Cocoa
import UniformTypeIdentifiers

private final class SAct: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}

private final class SFlippedDoc: NSView {
    override var isFlipped: Bool { true }
}

/// Editor for the time-of-day schedule. Each slot has a start time and a
/// source for Light and (optionally) Dark appearance; the slot in effect
/// is the latest one whose start time has passed, wrapping overnight.
final class ScheduleWindowController: NSWindowController {
    private let controller: WallpaperController
    var onChange: () -> Void = {}

    private let stack = NSStackView()
    private var actions: [SAct] = []
    private var slots: [WallpaperController.ScheduleSlot] = []

    init(controller: WallpaperController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Schedule"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 320)
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let intro = NSTextField(wrappingLabelWithString:
            "Play a different video at different times of day. The slot with "
            + "the most recent start time is used (wrapping past midnight). "
            + "Set a Dark source to auto-swap when macOS switches to Dark mode.")
        intro.textColor = .secondaryLabelColor
        intro.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = NSButton(title: "Add Time Slot", target: nil, action: nil)
        addBtn.bezelStyle = .rounded
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        let addA = SAct { [weak self] in self?.addSlot() }
        actions.append(addA); addBtn.target = addA; addBtn.action = #selector(SAct.fire)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = SFlippedDoc()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        content.addSubview(intro)
        content.addSubview(addBtn)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            intro.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            intro.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            addBtn.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 10),
            addBtn.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            scroll.topAnchor.constraint(equalTo: addBtn.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: doc.bottomAnchor, constant: -4),
        ])
    }

    func show() {
        slots = controller.scheduleSlots
        NSApp.activate(ignoringOtherApps: true)
        if let window { Appearance.register(window) }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        reload()
    }

    private func commit() {
        controller.setSchedule(slots)
        slots = controller.scheduleSlots   // canonical (sorted) order back
        onChange()
        reload()
    }

    private func dateFor(minutes: Int) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: minutes / 60, minute: minutes % 60,
                        second: 0, of: Date()) ?? Date()
    }

    private func minutesFrom(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func describe(_ src: WallpaperController.DisplaySource?) -> String {
        guard let src else { return "Not set" }
        let kind = src.kind == "playlist" ? "Folder" : "Video"
        return "\(kind): \((src.path as NSString).lastPathComponent)"
    }

    private func reload() {
        actions.removeAll(keepingCapacity: true)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if slots.isEmpty {
            let empty = NSTextField(labelWithString:
                "No time slots yet — click “Add Time Slot” to begin.")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
            return
        }

        for (idx, slot) in slots.enumerated() {
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 6

            // Time + remove.
            let head = NSStackView()
            head.orientation = .horizontal
            head.alignment = .centerY
            head.spacing = 10
            head.addArrangedSubview(NSTextField(labelWithString: "Starts at"))

            let picker = NSDatePicker()
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.dateValue = dateFor(minutes: slot.start)
            let timeA = SAct { [weak self, weak picker] in
                guard let self, let picker else { return }
                self.slots[idx].start = self.minutesFrom(picker.dateValue)
                self.commit()
            }
            actions.append(timeA)
            picker.target = timeA
            picker.action = #selector(SAct.fire)
            head.addArrangedSubview(picker)

            let remove = NSButton(title: "Remove", target: nil, action: nil)
            remove.bezelStyle = .rounded
            let remA = SAct { [weak self] in
                guard let self else { return }
                self.slots.remove(at: idx)
                self.commit()
            }
            actions.append(remA); remove.target = remA; remove.action = #selector(SAct.fire)
            head.addArrangedSubview(remove)
            row.addArrangedSubview(head)

            row.addArrangedSubview(sourceRow(label: "Light", idx: idx, isDark: false,
                                             src: slot.light))
            row.addArrangedSubview(sourceRow(label: "Dark", idx: idx, isDark: true,
                                             src: slot.dark))

            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            sep.widthAnchor.constraint(equalToConstant: 580).isActive = true
            row.addArrangedSubview(sep)

            stack.addArrangedSubview(row)
        }
    }

    private func sourceRow(label: String, idx: Int, isDark: Bool,
                           src: WallpaperController.DisplaySource?) -> NSView {
        let r = NSStackView()
        r.orientation = .horizontal
        r.alignment = .centerY
        r.spacing = 8

        let tag = NSTextField(labelWithString: "\(label):")
        tag.font = .boldSystemFont(ofSize: 12)
        tag.translatesAutoresizingMaskIntoConstraints = false
        tag.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let status = NSTextField(labelWithString: describe(src))
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.translatesAutoresizingMaskIntoConstraints = false
        status.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let file = NSButton(title: "File…", target: nil, action: nil)
        file.bezelStyle = .rounded
        let fileA = SAct { [weak self] in self?.pick(idx: idx, isDark: isDark, folder: false) }
        actions.append(fileA); file.target = fileA; file.action = #selector(SAct.fire)

        let fold = NSButton(title: "Folder…", target: nil, action: nil)
        fold.bezelStyle = .rounded
        let foldA = SAct { [weak self] in self?.pick(idx: idx, isDark: isDark, folder: true) }
        actions.append(foldA); fold.target = foldA; fold.action = #selector(SAct.fire)

        let clear = NSButton(title: "Clear", target: nil, action: nil)
        clear.bezelStyle = .rounded
        clear.isEnabled = (src != nil)
        let clearA = SAct { [weak self] in
            guard let self else { return }
            if isDark { self.slots[idx].dark = nil } else { self.slots[idx].light = nil }
            self.commit()
        }
        actions.append(clearA); clear.target = clearA; clear.action = #selector(SAct.fire)

        [tag, status, file, fold, clear].forEach { r.addArrangedSubview($0) }
        return r
    }

    private func addSlot() {
        let next: Int
        if let last = slots.map({ $0.start }).max() {
            next = (last + 60) % (24 * 60)
        } else {
            next = 8 * 60
        }
        slots.append(.init(start: next, light: nil, dark: nil))
        commit()
    }

    private func pick(idx: Int, isDark: Bool, folder: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        if folder {
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.message = "Playlist folder for this slot"
        } else {
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
            panel.message = "Video for this slot"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let src = WallpaperController.DisplaySource(
            kind: folder ? "playlist" : "single", path: url.path)
        if isDark { slots[idx].dark = src } else { slots[idx].light = src }
        commit()
    }
}
