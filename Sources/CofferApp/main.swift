import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

final class FittingText: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 18)
        }
        let width = bounds.width > 40 ? bounds.width : 220
        textContainer.containerSize = NSSize(width: width, height: 10_000)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let height = max(16, ceil(used.height + textContainerInset.height * 2))
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func layout() {
        super.layout()
        if abs(intrinsicContentSize.height - bounds.height) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }
}

enum ImportMode { case file, clipboard }

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
    let sidebar = NSTableView()
    let listPanel = NSBox()
    let inspectorPanel = NSView()
    let statusLabel = NSTextField(labelWithString: "已纳管 0 条")
    let pageLabel = NSTextField(labelWithString: "")
    var page = 0
    var pageSize = 12
    let nameLabel = NSTextField(labelWithString: "")
    let cliField = NSTextField(string: "")
    let pathField = FittingText()
    let commandField = FittingText()
    let detailEditor = NSTextView()
    let kindField = NSTextField(string: "")
    let staleLabel = NSTextField(labelWithString: "")
    let message = NSTextField(labelWithString: "")
    var credentials: [CredentialSummary] = []
    var candidates: [ImportCandidate] = []
    var shown: [Shown] = []
    var source = ""
    var sourcePath = ""
    var importMode = ImportMode.file
    var pastePayload = Data()
    var pendingPasteDetail = ""
    var pendingPasteKind = ""
    var kindFilter = ""
    var filterRow = NSStackView()
    var importAllButton: NSButton?

    /// Cmd+Q is delivered only through the application menu. A status-item menu
    /// is not that menu, and this app has no MainMenu nib.
    func installMainMenu() {
        let appMenu = NSMenu(title: "Ferret9")
        let quit = NSMenuItem(title: "退出 Ferret9", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu

        let main = NSMenu()
        main.addItem(appItem)
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func installStatusIcon() {
        guard let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            status.button?.title = "Ferret9"
            return
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        status.length = NSStatusItem.squareLength
        status.button?.image = image
        status.button?.imagePosition = .imageOnly
        status.button?.imageScaling = .scaleProportionallyDown
        status.button?.title = ""
        status.button?.toolTip = "Ferret9"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusIcon()
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开", action: #selector(show), keyEquivalent: "")
        openItem.target = self
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(openItem)
        menu.addItem(quitItem)
        status.menu = menu
        buildWindow()
        show()
    }

    func buildWindow() {
        window.title = "Ferret9"
        window.minSize = NSSize(width: 960, height: 560)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setContentSize(NSSize(width: 1140, height: 680))
        window.center()

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSStackView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.orientation = .horizontal
        bar.spacing = 12
        bar.alignment = .centerY
        let importBtn = primaryButton("导入", #selector(importMenu))
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let barSpacer = NSView()
        barSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(importBtn)
        bar.addArrangedSubview(barSpacer)
        bar.addArrangedSubview(statusLabel)

        listPanel.translatesAutoresizingMaskIntoConstraints = false
        listPanel.boxType = .custom
        listPanel.borderType = .lineBorder
        listPanel.borderWidth = 1
        listPanel.cornerRadius = 10
        listPanel.fillColor = NSColor.controlBackgroundColor
        listPanel.borderColor = NSColor.separatorColor

        let listHead = NSTextField(labelWithString: "已纳管配置")
        listHead.font = .systemFont(ofSize: 13, weight: .semibold)
        listHead.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        sidebar.intercellSpacing = NSSize(width: 0, height: 0)
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.headerView = NSTableHeaderView()
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.rowHeight = 32
        sidebar.intercellSpacing = NSSize(width: 0, height: 0)
        sidebar.allowsEmptySelection = false
        sidebar.usesAlternatingRowBackgroundColors = true
        sidebar.gridStyleMask = [.solidHorizontalGridLineMask]
        sidebar.backgroundColor = .clear
        sidebar.doubleAction = #selector(importSelected)
        sidebar.target = self
        for (id, title, width) in [("name", "名称", 220), ("kind", "类型", 90), ("desc", "说明", 240)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = CGFloat(width)
            column.minWidth = id == "kind" ? 72 : 140
            column.resizingMask = id == "desc" ? .autoresizingMask : .userResizingMask
            sidebar.addTableColumn(column)
        }
        sidebar.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        scroll.documentView = sidebar

        let prev = NSButton(title: "上一页", target: self, action: #selector(prevPage))
        prev.bezelStyle = .rounded
        prev.controlSize = .small
        let next = NSButton(title: "下一页", target: self, action: #selector(nextPage))
        next.bezelStyle = .rounded
        next.controlSize = .small
        pageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .center
        pageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let pager = NSStackView(views: [prev, pageLabel, next])
        pager.orientation = .horizontal
        pager.spacing = 8
        pager.alignment = .centerY
        pager.distribution = .fill
        pager.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let pagerHost = NSView()
        pagerHost.translatesAutoresizingMaskIntoConstraints = false
        pagerHost.addSubview(pager)

        listPanel.addSubview(listHead)
        filterRow.orientation = .horizontal
        filterRow.spacing = 6
        filterRow.alignment = .centerY
        filterRow.translatesAutoresizingMaskIntoConstraints = false
        listPanel.addSubview(filterRow)
        listPanel.addSubview(scroll)
        listPanel.addSubview(pagerHost)

        inspectorPanel.translatesAutoresizingMaskIntoConstraints = false
        inspectorPanel.wantsLayer = true
        inspectorPanel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        inspectorPanel.layer?.cornerRadius = 10
        inspectorPanel.layer?.borderWidth = 1
        inspectorPanel.layer?.borderColor = NSColor.separatorColor.cgColor

        let inspHead = NSTextField(labelWithString: "详情")
        inspHead.font = .systemFont(ofSize: 13, weight: .semibold)
        inspHead.translatesAutoresizingMaskIntoConstraints = false

        staleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        staleLabel.textColor = .systemOrange
        staleLabel.translatesAutoresizingMaskIntoConstraints = false
        staleLabel.maximumNumberOfLines = 2
        message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 2
        message.alignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false

        func plainField(_ field: NSTextField, mono: Bool) {
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = mono ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 13)
            field.lineBreakMode = .byTruncatingTail
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        plainField(cliField, mono: false)
        plainField(kindField, mono: false)
        cliField.isEditable = true
        kindField.isEditable = true
        func wrapField(_ field: FittingText) {
            field.isEditable = false
            field.isSelectable = true
            field.isRichText = false
            field.drawsBackground = false
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textContainerInset = NSSize(width: 0, height: 1)
            field.textContainer?.widthTracksTextView = false
            field.isHorizontallyResizable = false
            field.isVerticallyResizable = false
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        wrapField(pathField)
        wrapField(commandField)

        detailEditor.isEditable = true
        detailEditor.isRichText = false
        detailEditor.font = .systemFont(ofSize: 13)
        detailEditor.textContainerInset = NSSize(width: 2, height: 4)
        detailEditor.drawsBackground = false
        let detailScroll = NSScrollView()
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .noBorder
        detailScroll.drawsBackground = false
        detailScroll.documentView = detailEditor
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.heightAnchor.constraint(equalToConstant: 48).isActive = true
        detailScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)

        func fieldRow(_ title: String, _ control: NSView, _ action: NSButton? = nil, height: CGFloat? = 36) -> NSView {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .left
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.widthAnchor.constraint(equalToConstant: 40).isActive = true
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            var parts: [NSView] = [label, control]
            if let action {
                action.setContentHuggingPriority(.required, for: .horizontal)
                action.setContentCompressionResistancePriority(.required, for: .horizontal)
                parts.append(action)
            }
            let row = NSStackView(views: parts)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            if let height {
                row.heightAnchor.constraint(equalToConstant: height).isActive = true
            } else {
                row.alignment = .top
                row.distribution = .fill
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            }
            return row
        }
        func group(_ rows: [NSView]) -> NSView {
            let box = NSView()
            box.translatesAutoresizingMaskIntoConstraints = false
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            box.layer?.cornerRadius = 10
            box.layer?.borderWidth = 1
            box.layer?.borderColor = NSColor.separatorColor.cgColor
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.spacing = 0
            stack.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
                stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
            ])
            for (i, row) in rows.enumerated() {
                stack.addArrangedSubview(row)
                row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
                row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
                if i < rows.count - 1 {
                    let line = NSBox()
                    line.boxType = .separator
                    line.translatesAutoresizingMaskIntoConstraints = false
                    stack.addArrangedSubview(line)
                    line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                    line.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
                    line.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
                }
            }
            return box
        }

        let showBtn = linkButton("显示", #selector(revealInFinder))
        let testBtn = linkButton("测试", #selector(runTestCommand))
        let saveBtn = primaryButton("保存更改", #selector(saveDetail))
        let importAllBtn = primaryButton("全部入库", #selector(importAll))
        importAllButton = importAllBtn
        let delBtn = textDangerButton("从列表中移除…", #selector(remove))

        let groupA = group([
            fieldRow("名称", cliField),
            fieldRow("类型", kindField),
            fieldRow("说明", detailScroll, height: 56),
        ])
        let groupB = group([
            fieldRow("路径", pathField, showBtn, height: nil),
            fieldRow("命令", commandField, testBtn, height: nil),
        ])

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)

        let foot = NSStackView()
        foot.orientation = .vertical
        foot.spacing = 6
        foot.alignment = .centerX
        foot.translatesAutoresizingMaskIntoConstraints = false
        foot.addArrangedSubview(importAllBtn)
        foot.addArrangedSubview(saveBtn)
        foot.addArrangedSubview(delBtn)
        foot.addArrangedSubview(message)
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        importAllBtn.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [inspHead, groupA, groupB, staleLabel, spacer, foot])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        inspectorPanel.addSubview(column)

        let split = NSStackView(views: [listPanel, inspectorPanel])
        split.orientation = .horizontal
        split.spacing = 16
        split.alignment = .height
        split.distribution = .fill
        split.translatesAutoresizingMaskIntoConstraints = false
        listPanel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        listPanel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        inspectorPanel.setContentHuggingPriority(.required, for: .horizontal)
        inspectorPanel.setContentCompressionResistancePriority(.required, for: .horizontal)
        inspectorPanel.widthAnchor.constraint(equalToConstant: 380).isActive = true

        root.addSubview(bar)
        root.addSubview(split)
        window.contentView = root
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize), name: NSWindow.didResizeNotification, object: window)

        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            split.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 14),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -pad),
            listPanel.heightAnchor.constraint(equalTo: split.heightAnchor),
            inspectorPanel.heightAnchor.constraint(equalTo: split.heightAnchor),
            listHead.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor, constant: 14),
            listHead.topAnchor.constraint(equalTo: listPanel.topAnchor, constant: 12),
            filterRow.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor, constant: 14),
            filterRow.trailingAnchor.constraint(equalTo: listPanel.trailingAnchor, constant: -14),
            filterRow.topAnchor.constraint(equalTo: listHead.bottomAnchor, constant: 8),
            filterRow.heightAnchor.constraint(equalToConstant: 24),
            scroll.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: listPanel.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: pagerHost.topAnchor, constant: -64),
            pagerHost.leadingAnchor.constraint(equalTo: listPanel.leadingAnchor, constant: 10),
            pagerHost.trailingAnchor.constraint(equalTo: listPanel.trailingAnchor, constant: -10),
            pagerHost.bottomAnchor.constraint(equalTo: listPanel.bottomAnchor, constant: -8),
            pagerHost.heightAnchor.constraint(equalToConstant: 28),
            pager.centerXAnchor.constraint(equalTo: pagerHost.centerXAnchor),
            pager.centerYAnchor.constraint(equalTo: pagerHost.centerYAnchor),
            column.leadingAnchor.constraint(equalTo: inspectorPanel.leadingAnchor, constant: 14),
            column.trailingAnchor.constraint(equalTo: inspectorPanel.trailingAnchor, constant: -14),
            column.topAnchor.constraint(equalTo: inspectorPanel.topAnchor, constant: 14),
            column.bottomAnchor.constraint(equalTo: inspectorPanel.bottomAnchor, constant: -14),
            groupA.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            groupA.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            groupB.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            groupB.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            staleLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            staleLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            foot.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            foot.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            saveBtn.widthAnchor.constraint(equalTo: foot.widthAnchor),
            importAllBtn.widthAnchor.constraint(equalTo: foot.widthAnchor),
        ])
    }

    func primaryButton(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        if #available(macOS 12.0, *) {
            b.bezelColor = NSColor(red: 0.91, green: 0.54, blue: 0.16, alpha: 1)
            b.contentTintColor = .white
        }
        return b
    }
    func linkButton(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .inline
        b.isBordered = false
        b.contentTintColor = .linkColor
        b.font = .systemFont(ofSize: 12, weight: .regular)
        return b
    }
    func textDangerButton(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .inline
        b.isBordered = false
        b.contentTintColor = .systemRed
        b.font = .systemFont(ofSize: 12, weight: .medium)
        return b
    }

    func bringForward() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringForward()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible { window.makeKeyAndOrderFront(nil) }
        else { window.orderFrontRegardless() }
    }

    @objc func show() { bringForward(); reload() }
    @objc func reload() {
        candidates = []
        source = ""
        sourcePath = ""
        pastePayload = Data()
        importMode = .file
        respond(.list)
    }
    @objc func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        importMode = .clipboard
        source = url.lastPathComponent
        sourcePath = url.path
        pastePayload = data
        respond(.inspectText(label: source, contentBase64: data.base64EncodedString()))
    }
    @objc func pasteInspect() {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        let panel = NSAlert()
        panel.messageText = "粘贴导入"
        panel.informativeText = "正文来自剪贴板（可先在下方粘贴区改动）。文件名与放入目录必填。"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        func fld(_ y: CGFloat, _ label: String, _ def: String, req: Bool) -> NSTextField {
            let l = NSTextField(labelWithString: label + (req ? " *" : ""))
            l.frame = NSRect(x: 0, y: y + 22, width: 88, height: 18)
            l.font = .systemFont(ofSize: 11)
            let t = NSTextField(frame: NSRect(x: 92, y: y, width: 308, height: 22))
            t.stringValue = def
            box.addSubview(l); box.addSubview(t)
            return t
        }
        let fName = fld(170, "文件名", "", req: true)
        let fDir = fld(130, "放入目录", "~/.aliyun", req: true)
        let fDesc = fld(90, "说明", "", req: false)
        let fKind = fld(50, "类型", "aliyun", req: false)
        let body = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        body.stringValue = clip
        box.addSubview(NSTextField(labelWithString: "正文"))
        box.subviews.last!.frame = NSRect(x: 0, y: 32, width: 40, height: 16)
        body.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
        box.addSubview(body)
        panel.accessoryView = box
        panel.addButton(withTitle: "分析")
        panel.addButton(withTitle: "取消")
        guard panel.runModal() == .alertFirstButtonReturn else { return }
        let name = fName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = fDir.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = body.stringValue
        guard !name.isEmpty, !dir.isEmpty, !payload.isEmpty else {
            message.stringValue = "文件名、目录、正文不能为空"
            return
        }
        importMode = .clipboard
        source = name
        let expanded = (dir as NSString).expandingTildeInPath
        sourcePath = (expanded as NSString).appendingPathComponent(name)
        pastePayload = Data(payload.utf8)
        pendingPasteDetail = fDesc.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingPasteKind = fKind.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        respond(.inspectText(label: name, contentBase64: pastePayload.base64EncodedString()))
    }
    @objc func importSelected() {
        guard !candidates.isEmpty else { message.stringValue = "先分析"; return }
        let rows = sidebar.selectedRowIndexes
        let pick = rows.isEmpty ? candidates : rows.compactMap { row in
            guard shown.indices.contains(shownIndex(for: row)), case .candidate(let item) = shown[shownIndex(for: row)].value else { return nil }
            return item
        }
        let auth = ticket()
        guard !auth.isEmpty else { message.stringValue = "需要授权"; return }
        for item in pick {
            respond(.addInline(name: item.name, label: source, contentBase64: pastePayload.base64EncodedString(), origin: sourcePath.isEmpty ? nil : sourcePath, overrideName: nil, overrideKind: nil, overrideDetail: nil, authorization: auth))
            if message.stringValue.hasPrefix("已添加") || message.stringValue.hasPrefix("已存在") {
                candidates.removeAll { $0.name == item.name }
            }
        }
        if credentials.isEmpty { respond(.list); return }
        rebuild()
    }

    @objc func importAll() {
        guard !candidates.isEmpty else { message.stringValue = "没有待入库的条目"; return }
        let auth = ticket()
        guard !auth.isEmpty else { message.stringValue = "需要授权"; return }
        let pending = candidates
        var added = 0
        var failed: [String] = []
        for item in pending {
            respond(.addInline(name: item.name, label: source, contentBase64: pastePayload.base64EncodedString(), origin: sourcePath.isEmpty ? nil : sourcePath, overrideName: nil, overrideKind: nil, overrideDetail: nil, authorization: auth))
            if message.stringValue.hasPrefix("已添加") || message.stringValue.hasPrefix("已存在") {
                candidates.removeAll { $0.name == item.name }
                added += 1
            } else {
                failed.append(item.name)
            }
        }
        if credentials.isEmpty { respond(.list) } else { rebuild() }
        if failed.isEmpty {
            message.stringValue = "已入库 \(added) 条"
        } else {
            message.stringValue = "入库 \(added) 条，失败 \(failed.count) 条：\(failed.joined(separator: "、"))"
        }
    }

    @objc func rename() {
        guard let name = selectedCredential() else { return }
        let alert = NSAlert()
        alert.messageText = "新的说明"
        let current = credentials.first { $0.name == name }?.detail ?? ""
        alert.informativeText = current.isEmpty ? "当前没有说明" : "当前说明：\(current)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        respond(.update(name: name, detail: field.stringValue, kind: nil, rename: nil, source: nil, authorization: ticket()))
    }
    @objc func replace() {
        guard let name = selectedCredential() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        respond(.updateInline(name: name, label: url.lastPathComponent, contentBase64: data.base64EncodedString(), authorization: ticket()))
    }
    @objc func test() {
        guard let name = selectedCredential() else { return }
        respond(.test(name: name))
    }
    @objc func remove() {
        guard let name = selectedCredential() else { return }
        respond(.delete(name: name, authorization: ticket()))
    }
    @objc func openSource() {
        guard let row = current(), case .credential = row.value else { message.stringValue = "先选已入库的一条"; return }
        guard let path = row.origin, FileManager.default.fileExists(atPath: path) else {
            message.stringValue = row.origin == nil ? "这条没有记录原始路径" : "原文件不在了"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
    @objc func copyCommand() {
        guard let row = current(), !row.command.isEmpty else { message.stringValue = "这条没有可复制的命令"; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.command, forType: .string)
        message.stringValue = "已复制命令"
    }

    @objc func importMenu() {
        let alert = NSAlert()
        alert.messageText = "导入"
        alert.informativeText = "选择文件：选取后自动分析并在右侧列表勾选入库。粘贴：填写文件名、放入目录、可选说明与类型后分析。"
        alert.addButton(withTitle: "选择文件")
        alert.addButton(withTitle: "粘贴内容")
        alert.addButton(withTitle: "取消")
        let r = alert.runModal()
        if r == .alertFirstButtonReturn { importFile() }
        else if r == .alertSecondButtonReturn { pasteInspect() }
    }

    @objc func saveDetail() {
        guard let row = current() else { return }
        let detail = detailEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = kindField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = cliField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { message.stringValue = "名称不能为空"; return }
        let auth = ticket()
        guard !auth.isEmpty else { message.stringValue = "需要授权"; return }
        if case .candidate(let item) = row.value {
            respond(.addInline(name: item.name, label: source, contentBase64: pastePayload.base64EncodedString(), origin: sourcePath.isEmpty ? nil : sourcePath, overrideName: newName, overrideKind: kind.isEmpty ? nil : kind, overrideDetail: detail.isEmpty ? nil : detail, authorization: auth))
            if message.stringValue.hasPrefix("已添加") || message.stringValue.hasPrefix("已存在") {
                candidates.removeAll { $0.name == item.name }
            }
            if credentials.isEmpty { respond(.list); return }
            rebuild()
            return
        }
        guard case .credential = row.value else { return }
        respond(.update(name: row.title, detail: detail.isEmpty ? nil : detail, kind: kind.isEmpty ? nil : kind, rename: newName == row.title ? nil : newName, source: nil, authorization: auth))
    }

    @objc func revealInFinder() {
        guard let row = current(), let path = row.origin else {
            message.stringValue = "没有原始路径"
            return
        }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        let check = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if !check {
            message.stringValue = "路径不存在"
            return
        }
        let reveal = isDir.boolValue ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([reveal])
    }

    @objc func runTestCommand() {
        test()
    }

    func respond(_ req: Request) {
        var keep = current()?.title
        do {
            let res = try Client.call(req)
            message.stringValue = res.message
            if let report = res.inspect, res.message.isEmpty {
                var parts = ["编码 \(report.encoding)", "分段 \(report.segmentCount)"]
                if !report.attempts.isEmpty { parts.append("检测 \(report.attempts.prefix(8).joined(separator: ","))") }
                message.stringValue = parts.joined(separator: " · ")
            }
            if case .test = req {
                return
            }
            guard res.ok else { return }
            if case .update(let name, _, let kind, let rename, _, _) = req {
                keep = (rename?.isEmpty == false) ? rename : name
                if let kind, !kind.isEmpty, !kindFilter.isEmpty, kind != kindFilter {
                    kindFilter = ""
                }
            }
            if case .inspect = req {
            } else if case .inspectText = req {
            } else {
                credentials = res.credentials
                candidates = []
                rebuild(select: keep)
                return
            }
            candidates = res.candidates
            rebuild()
        } catch {
            message.stringValue = error.localizedDescription
        }
    }

    func pageCount() -> Int { max(1, Int(ceil(Double(shown.count) / Double(max(pageSize, 1))))) }

    func fitPageSize() {
        let header: CGFloat = max(sidebar.headerView?.frame.height ?? 0, 23)
        let usable = sidebar.enclosingScrollView?.contentSize.height ?? 0
        let pitch = sidebar.rowHeight + sidebar.intercellSpacing.height
        let fitted = max(0, Int(floor(max(0, usable - header) / pitch)) - 1)
        let next = max(1, fitted)
        if next == pageSize { page = min(page, pageCount() - 1); return }
        pageSize = next
        page = min(page, pageCount() - 1)
        sidebar.reloadData()
    }

    @objc func prevPage() {
        page = max(0, page - 1)
        sidebar.reloadData()
        updatePager()
    }

    @objc func nextPage() {
        page = min(pageCount() - 1, page + 1)
        sidebar.reloadData()
        updatePager()
    }

    @objc func windowDidResize() {
        fitPageSize()
        updatePager()
    }

    func updatePager() {
        let pages = pageCount()
        pageLabel.stringValue = "\(page + 1) / \(pages)"
        if !candidates.isEmpty {
            statusLabel.stringValue = "已纳管 \(credentials.count) 条 · 待入库 \(candidates.count) 条"
        } else {
            statusLabel.stringValue = "已纳管 \(credentials.count) 条"
        }
        importAllButton?.isHidden = candidates.isEmpty
        refreshFilters()
    }

    func refreshFilters() {
        let kinds = Array(Set(credentials.map(\.kind))).sorted()
        if !kindFilter.isEmpty && !kinds.contains(kindFilter) { kindFilter = "" }
        for view in filterRow.arrangedSubviews { filterRow.removeArrangedSubview(view); view.removeFromSuperview() }
        guard kinds.count > 1 else { return }
        for label in ["全部"] + kinds {
            let button = NSButton(title: label, target: self, action: #selector(filterKind(_:)))
            button.bezelStyle = .recessed
            button.setButtonType(.pushOnPushOff)
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            let active = (label == "全部" && kindFilter.isEmpty) || label == kindFilter
            button.state = active ? .on : .off
            filterRow.addArrangedSubview(button)
        }
    }

    @objc func filterKind(_ sender: NSButton) {
        kindFilter = sender.title == "全部" ? "" : sender.title
        page = 0
        rebuild()
    }

    func shownIndex(for row: Int) -> Int { page * pageSize + row }

    func rebuild(select keep: String? = nil) {
        let keep = keep ?? current()?.title
        let pool = kindFilter.isEmpty ? credentials : credentials.filter { $0.kind == kindFilter }
        let pending = candidates.map { Shown.candidate($0, sourcePath) }
        shown = pending + Shown.grouped(pool)
        sidebar.reloadData()
        fitPageSize()
        updatePager()
        let restored = keep.flatMap { name in shown.firstIndex { $0.title == name } }
        if let restored {
            selectShown(at: restored)
        } else if let first = shown.firstIndex(where: { if case .credential = $0.value { return true }; return false }) {
            selectShown(at: first)
        } else if !shown.isEmpty {
            selectShown(at: 0)
        }
        showSelection()
    }

    func selectShown(at index: Int) {
        guard shown.indices.contains(index) else { return }
        let size = max(pageSize, 1)
        let newPage = index / size
        if newPage != page {
            page = newPage
            sidebar.reloadData()
            updatePager()
        }
        sidebar.selectRowIndexes(IndexSet(integer: index - page * size), byExtendingSelection: false)
    }

    func current() -> Shown? {
        let index = shownIndex(for: sidebar.selectedRow)
        guard shown.indices.contains(index) else { return nil }
        return shown[index]
    }
    func selectedCredential() -> String? {
        guard let row = current(), case .credential(let item) = row.value else {
            if !credentials.isEmpty { message.stringValue = "选已入库的一条" }
            return nil
        }
        return item.name
    }
    func ticket() -> String { (try? Grant.issue()) ?? "" }

    func numberOfRows(in tableView: NSTableView) -> Int {
        let start = page * pageSize
        return max(0, min(pageSize, shown.count - start))
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { sidebar.rowHeight }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let index = shownIndex(for: row)
        guard shown.indices.contains(index) else { return nil }
        let item = shown[index]
        let id = tableColumn?.identifier.rawValue ?? "name"
        let value: String
        switch id {
        case "kind": value = item.kind
        case "desc": value = item.detailText
        case "path": value = item.pathText
        case "open": value = item.openText
        default: value = item.title
        }
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: value)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        text.font = (id == "name" || id == "desc") ? .systemFont(ofSize: id == "desc" ? 11 : 13) : .monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
    func tableViewSelectionDidChange(_ notification: Notification) { showSelection() }

    func showSelection() {
        guard let row = current() else {
            window.title = "Ferret9"
            cliField.stringValue = ""
            kindField.stringValue = ""
            detailEditor.string = ""
            pathField.string = ""
            commandField.string = ""
            staleLabel.stringValue = ""
            return
        }
        window.title = "Ferret9 — \(row.title)"
        if case .candidate(let item) = row.value {
            cliField.stringValue = item.name
        } else {
            cliField.stringValue = row.title
        }
        kindField.stringValue = row.kind
        let d = row.detailText
        detailEditor.string = (d == "（无说明）" || d.hasPrefix("（导入")) ? "" : d
        pathField.string = row.pathText
        commandField.string = row.command
        staleLabel.stringValue = row.stale
    }
}

struct Shown {
    enum Value { case heading, credential(CredentialSummary), candidate(ImportCandidate) }
    var value: Value
    var title: String
    var heading: Bool
    var kind: String
    var pathText: String
    var command: String
    var openText: String
    var stale: String
    var origin: String?
    var detailText: String
    var cliHint: String

    static func candidate(_ item: ImportCandidate, _ path: String) -> Shown {
        let usage = Usage.lookup(name: item.name, kind: item.kind, path: path.isEmpty ? nil : path)
        return Shown(value: .candidate(item), title: "待入库 · \(item.name)", heading: false, kind: item.kind,
                     pathText: path.isEmpty ? "粘贴内容，没有原文件" : (NSString(string: path).abbreviatingWithTildeInPath),
                     command: usage.command, openText: usage.open, stale: "", origin: path.isEmpty ? nil : path,
                     detailText: item.detail.isEmpty ? "（导入预览，尚未入库）" : item.detail,
                     cliHint: Usage.cliName(kind: item.kind))
    }

    static func grouped(_ items: [CredentialSummary]) -> [Shown] {
        let kinds = Array(Set(items.map(\.kind))).sorted()
        var rows: [Shown] = []
        for kind in kinds {
            for item in items.filter({ $0.kind == kind }).sorted(by: { $0.name < $1.name }) {
                let known = Catalog.match(item.name)
                let path = item.source ?? OriginLookup.locate(name: item.name, kind: item.kind) ?? known?.path
                let usage = Usage.lookup(name: item.name, kind: item.kind, path: path)
                let display = path.map { NSString(string: $0).abbreviatingWithTildeInPath } ?? "未记录原始路径"
                rows.append(Shown(value: .credential(item), title: item.name, heading: false, kind: item.kind,
                                  pathText: display, command: usage.command, openText: usage.open,
                                  stale: Catalog.stale(path), origin: path,
                                  detailText: item.detail.isEmpty ? "（无说明）" : item.detail,
                                  cliHint: Usage.cliName(kind: item.kind)))
            }
        }
        return rows
    }
}

struct Usage {
    var command: String
    var open: String
    static func cliName(kind: String) -> String {
        switch kind {
        case "kubeconfig": return "kubectl cli"
        case "aliyun": return "aliyun cli"
        case "ossutil": return "ossutil cli"
        case "private-key": return "ssh cli"
        case "github": return "gh cli"
        case "tcloud": return "tccli"
        case "redis": return "redis-cli"
        default: return kind
        }
    }
    static func lookup(name: String, kind: String, path: String?) -> Usage {
        let shown = path.map { NSString(string: $0).abbreviatingWithTildeInPath } ?? ""
        switch kind {
        case "kubeconfig":
            let file = shown.isEmpty ? "<原文件>" : shown
            return Usage(command: "kubectl --kubeconfig \(file) get ns", open: "用 kubectl。原文件可用编辑器打开。")
        case "aliyun":
            if name.hasPrefix("zshrc-") {
                return Usage(command: "source ~/.zshrc", open: "环境变量在 ~/.zshrc。改完要重新 source，不会自动进库。")
            }
            let file = shown.isEmpty ? "~/.aliyun/config.json" : shown
            return Usage(command: "aliyun --config-path \(file) configure list", open: "用 aliyun --config-path。原文件可用编辑器打开。")
        case "ossutil":
            let file = shown.isEmpty ? "~/.ossutilconfig" : shown
            return Usage(command: "ossutil ls -c \(file)", open: "用 ossutil -c。原文件可用编辑器打开。")
        case "aws":
            return Usage(command: "aws sts get-caller-identity", open: "aws 读 ~/.aws/credentials。没有按单文件切换的命令。")
        case "private-key":
            let file = shown.isEmpty ? "<私钥>" : shown
            return Usage(command: "ssh -i \(file)", open: "用 ssh -i。不要用文本编辑器改私钥。")
        case "redis":
            return Usage(command: "redis-cli -h <这条的 host>", open: "redis-cli 在本机。host 在 ~/.redis/config.yaml，命令里不代填。")
        case "cloudflare":
            return Usage(command: shown.isEmpty ? "" : "open \(shown)", open: "本机没有 wrangler。用编辑器打开原文件。")
        case "feishu":
            return Usage(command: shown.isEmpty ? "" : "open \(shown)", open: "本机没有飞书命令行。用编辑器打开原文件。")
        case "github":
            return Usage(command: "gh auth status",
                         open: "gh 读的是钥匙串，不读这个文件。")
        case "tcloud":
            return Usage(command: "tccli tke DescribeClusters --region <region>",
                         open: "用 tccli。密钥由 ferret9 run 放进环境变量，不进参数。region 要写在命令里。")
        default:
            return Usage(command: shown.isEmpty ? "" : "open \(shown)", open: "没有对应命令。用编辑器打开原文件。")
        }
    }
}

enum Catalog {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static func match(_ name: String) -> (path: String, note: String)? {
        // Example mapping only. Ferret9 does not store the source path, so a
        // real install replaces this table with its own names. Nothing here is a
        // credential that ships with the app.
        let table: [(String, String)] = [
            ("example-dev", ".kube/example-dev"),
            ("example-prod", ".kube/example-prod"),
            ("example-cloud", ".aliyun/config.json"),
            ("example-oss", ".ossutilconfig"),
            ("example-aws", ".aws/credentials"),
            ("example-dns", ".cloudflare/config.yaml"),
            ("example-github", ".github/token.yaml"),
            ("example-cache", ".redis/config.yaml"),
            ("example-key", ".ssh/id_ed25519")
        ]
        guard let hit = table.first(where: { $0.0 == name }) else { return nil }
        return (home + "/" + hit.1, hit.1)
    }
    static func stale(_ path: String?) -> String {
        guard let path else { return "" }
        guard FileManager.default.fileExists(atPath: path) else { return "原文件不在这个路径了" }
        return ""
    }
}
