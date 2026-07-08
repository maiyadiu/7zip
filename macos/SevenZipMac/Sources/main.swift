import AppKit

private let archiveExtensions: Set<String> = [
  "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst",
  "tzst", "cab", "iso", "dmg", "wim", "esd"
]

private enum ArchiveMode {
  case extract
  case compress
}

private enum ExtractionDestinationMode {
  case containingDirectory
  case sameNameFolder
}

private final class ArchiveTaskRunner {
  enum RunnerError: Error, LocalizedError {
    case missingEngine

    var errorDescription: String? {
      switch self {
      case .missingEngine:
        return "没有找到内置的 7zz 压缩引擎。"
      }
    }
  }

  private let engineURL: URL

  init() throws {
    guard let url = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
      throw RunnerError.missingEngine
    }

    engineURL = url
  }

  func run(
    arguments: [String],
    workingDirectory: URL?,
    output: @escaping (String) -> Void,
    completion: @escaping (Int32) -> Void
  ) {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = engineURL
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.standardOutput = pipe
    process.standardError = pipe

    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      let text = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .macOSRoman)
        ?? ""
      DispatchQueue.main.async {
        output(text)
      }
    }

    process.terminationHandler = { proc in
      pipe.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async {
        completion(proc.terminationStatus)
      }
    }

    do {
      try process.run()
    } catch {
      pipe.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async {
        output("启动 7zz 失败：\(error.localizedDescription)\n")
        completion(1)
      }
    }
  }
}

private class RoundedPanelView: NSView {
  var fillColor: NSColor = .controlBackgroundColor {
    didSet { layer?.backgroundColor = fillColor.cgColor }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
    layer?.backgroundColor = fillColor.cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    layer?.borderWidth = 1
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class DropZoneView: RoundedPanelView {
  var onDrop: (([URL]) -> Void)?
  private let titleLabel = NSTextField(labelWithString: "拖入文件、文件夹或压缩包")
  private let subtitleLabel = NSTextField(labelWithString: "自动识别压缩或解压任务")
  private let iconView = NSImageView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
    registerForDraggedTypes([.fileURL])
    setup()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    layer?.borderColor = NSColor.controlAccentColor.cgColor
    layer?.borderWidth = 2
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    layer?.borderWidth = 1
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    defer { draggingExited(nil) }
    let urls = Self.fileURLs(from: sender.draggingPasteboard)
    guard !urls.isEmpty else { return false }
    onDrop?(urls)
    return true
  }

  static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
    return objects ?? []
  }

  private func setup() {
    iconView.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "压缩包")
    iconView.symbolConfiguration = .init(pointSize: 36, weight: .regular)
    iconView.contentTintColor = .controlAccentColor

    titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
    titleLabel.alignment = .center
    subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.alignment = .center

    let stack = NSStackView(views: [iconView, titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(stack)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 220),
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 48),
      iconView.heightAnchor.constraint(equalToConstant: 48)
    ])
  }
}

private final class MainViewController: NSViewController {
  private var selectedURLs: [URL] = []
  private var destinationURL: URL?
  private var mode: ArchiveMode = .extract
  private var isRunning = false

  private let modeControl = NSSegmentedControl(labels: ["解压", "压缩"], trackingMode: .selectOne, target: nil, action: nil)
  private let dropZone = DropZoneView()
  private let fileList = NSTextView()
  private let formatPopup = NSPopUpButton()
  private let destinationLabel = NSTextField(labelWithString: "输出位置：自动")
  private let passwordField = NSSecureTextField()
  private let encryptHeaderButton = NSButton(checkboxWithTitle: "加密 7z 文件名", target: nil, action: nil)
  private let logView = NSTextView()
  private let runButton = NSButton(title: "开始", target: nil, action: nil)

  override func loadView() {
    view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    buildUI()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    modeControl.selectedSegment = 0
    modeControl.target = self
    modeControl.action = #selector(modeChanged)

    runButton.target = self
    runButton.action = #selector(startSelectedOperation)

    dropZone.onDrop = { [weak self] urls in
      self?.accept(urls: urls)
    }

    formatPopup.addItems(withTitles: ["7z", "zip"])
    passwordField.placeholderString = "可选密码"
    updateSelectionSummary()
    appendLog("已就绪。添加文件，或把压缩包拖进窗口开始处理。\n")
  }

  func accept(urls: [URL]) {
    selectedURLs = urls
    if urls.allSatisfy({ Self.isArchive($0) }) {
      setMode(.extract)
    } else {
      setMode(.compress)
    }
    destinationURL = nil
    updateSelectionSummary()
  }

  func openArchivesAndExtract(urls: [URL]) {
    let archives = urls.filter { Self.isArchive($0) }
    guard !archives.isEmpty else {
      accept(urls: urls)
      return
    }

    prepareExtraction(
      urls: archives,
      destinationMode: .containingDirectory,
      quitWhenFinished: true,
      note: "双击打开：自动解压到压缩包所在文件夹。\n"
    )
  }

  func prepareExtraction(
    urls: [URL],
    destinationMode: ExtractionDestinationMode,
    quitWhenFinished: Bool,
    note: String? = nil
  ) {
    selectedURLs = urls.filter { Self.isArchive($0) }
    setMode(.extract)
    destinationURL = nil
    updateSelectionSummary()
    if let note {
      appendLog(note)
    }
    startExtract(destinationMode: destinationMode, quitWhenFinished: quitWhenFinished)
  }

  func prepareCompression(urls: [URL], format: String, quitWhenFinished: Bool) {
    selectedURLs = urls
    setMode(.compress)
    destinationURL = nil
    formatPopup.selectItem(withTitle: format)
    updateSelectionSummary()
    appendLog("Finder 服务：压缩为 \(format)。\n")
    startCompress(quitWhenFinished: quitWhenFinished)
  }

  @objc private func modeChanged() {
    mode = modeControl.selectedSegment == 0 ? .extract : .compress
    updateSelectionSummary()
  }

  @objc private func addFiles() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.prompt = "添加"

    panel.begin { [weak self] response in
      guard response == .OK else { return }
      self?.accept(urls: panel.urls)
    }
  }

  @objc private func clearFiles() {
    selectedURLs = []
    destinationURL = nil
    updateSelectionSummary()
  }

  @objc private func chooseDestination() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"

    panel.begin { [weak self] response in
      guard response == .OK else { return }
      self?.destinationURL = panel.url
      self?.updateSelectionSummary()
    }
  }

  @objc private func startSelectedOperation() {
    guard !isRunning else { return }
    guard !selectedURLs.isEmpty else {
      showAlert(message: "还没有选择文件", information: "请先添加文件、文件夹或压缩包。")
      return
    }

    switch mode {
    case .extract:
      startExtract(destinationMode: .sameNameFolder, quitWhenFinished: false)
    case .compress:
      startCompress(quitWhenFinished: false)
    }
  }

  private func startExtract(destinationMode: ExtractionDestinationMode, quitWhenFinished: Bool) {
    let archives = selectedURLs.filter { Self.isArchive($0) }
    guard !archives.isEmpty else {
      showAlert(message: "没有可解压的压缩包", information: "解压操作需要一个或多个支持的压缩包文件。")
      return
    }

    runButton.isEnabled = false
    isRunning = true
    appendLog("\n开始解压 \(archives.count) 个压缩包...\n")

    var queue = archives
    var outputURLs: [URL] = []
    func runNext() {
      guard !queue.isEmpty else {
        finishRun(revealURLs: outputURLs, quitWhenFinished: quitWhenFinished)
        return
      }

      let archive = queue.removeFirst()
      let output = extractionDestination(for: archive, multipleArchives: archives.count > 1, mode: destinationMode)
      do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      } catch {
        appendLog("无法创建输出目录 \(output.path)：\(error.localizedDescription)\n")
        runNext()
        return
      }

      let args = extractionArguments(archive: archive, output: output)
      appendLog("正在解压 \(archive.lastPathComponent) -> \(output.path)\n")
      run7zz(arguments: args, workingDirectory: archive.deletingLastPathComponent()) { [weak self] status in
        self?.appendLog(status == 0 ? "完成：\(archive.lastPathComponent)\n" : "失败：\(archive.lastPathComponent)，退出码=\(status)\n")
        if status == 0 {
          outputURLs.append(output)
        }
        runNext()
      }
    }

    runNext()
  }

  private func startCompress(quitWhenFinished: Bool) {
    let format = formatPopup.titleOfSelectedItem ?? "7z"
    guard let output = archiveOutputURL(format: format) else {
      showAlert(message: "无法确定压缩包名称", information: "请选择位于可写目录中的文件或文件夹。")
      return
    }

    runButton.isEnabled = false
    isRunning = true

    let workingDirectory = commonDirectory(for: selectedURLs)
    let paths = selectedURLs.map { relativePath(for: $0, from: workingDirectory) }
    var args = ["a", output.path, "-t\(format)"]

    let password = passwordField.stringValue
    if !password.isEmpty {
      args.append("-p\(password)")
      if format == "7z", encryptHeaderButton.state == .on {
        args.append("-mhe=on")
      }
    }
    args.append(contentsOf: paths)

    appendLog("\n正在创建 \(output.path)\n")
    run7zz(arguments: args, workingDirectory: workingDirectory) { [weak self] status in
      self?.appendLog(status == 0 ? "压缩包已创建。\n" : "压缩失败，退出码=\(status)\n")
      self?.finishRun(revealURLs: status == 0 ? [output] : [], quitWhenFinished: quitWhenFinished)
    }
  }

  private func run7zz(arguments: [String], workingDirectory: URL?, completion: @escaping (Int32) -> Void) {
    do {
      let runner = try ArchiveTaskRunner()
      runner.run(arguments: arguments, workingDirectory: workingDirectory, output: { [weak self] text in
        self?.appendLog(text)
      }, completion: completion)
    } catch {
      appendLog("\(error.localizedDescription)\n")
      completion(1)
    }
  }

  private func finishRun(revealURLs: [URL], quitWhenFinished: Bool) {
    isRunning = false
    runButton.isEnabled = true
    appendLog("全部任务已完成。\n")
    if !revealURLs.isEmpty {
      NSWorkspace.shared.activateFileViewerSelecting(revealURLs)
    }
    if quitWhenFinished {
      NSApp.terminate(nil)
    }
  }

  private func extractionArguments(archive: URL, output: URL) -> [String] {
    var args = ["x", archive.path, "-o\(output.path)", "-y"]
    let password = passwordField.stringValue
    if !password.isEmpty {
      args.append("-p\(password)")
    }
    return args
  }

  private func extractionDestination(for archive: URL, multipleArchives: Bool, mode: ExtractionDestinationMode) -> URL {
    if let destinationURL {
      if multipleArchives {
        return destinationURL.appendingPathComponent(archive.deletingPathExtension().lastPathComponent, isDirectory: true)
      }
      return destinationURL
    }

    let parent = archive.deletingLastPathComponent()
    switch mode {
    case .containingDirectory:
      return parent
    case .sameNameFolder:
      return parent.appendingPathComponent(archive.deletingPathExtension().lastPathComponent, isDirectory: true)
    }
  }

  private func archiveOutputURL(format: String) -> URL? {
    let baseDirectory = destinationURL ?? selectedURLs.first?.deletingLastPathComponent()
    guard let baseDirectory else { return nil }

    let baseName: String
    if selectedURLs.count == 1 {
      baseName = selectedURLs[0].deletingPathExtension().lastPathComponent
    } else {
      baseName = "压缩包"
    }

    return baseDirectory.appendingPathComponent("\(baseName).\(format)")
  }

  private func commonDirectory(for urls: [URL]) -> URL {
    let directories = urls.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
    guard var common = directories.first else {
      return URL(fileURLWithPath: NSHomeDirectory())
    }

    for components in directories.dropFirst() {
      common = Array(zip(common, components).prefix { $0 == $1 }.map { $0.0 })
    }

    let path = NSString.path(withComponents: common)
    return URL(fileURLWithPath: path.isEmpty ? "/" : path, isDirectory: true)
  }

  private func relativePath(for url: URL, from base: URL) -> String {
    let basePath = base.standardizedFileURL.path
    let filePath = url.standardizedFileURL.path
    let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
    guard filePath.hasPrefix(prefix) else { return filePath }
    return String(filePath.dropFirst(prefix.count))
  }

  private static func isArchive(_ url: URL) -> Bool {
    archiveExtensions.contains(url.pathExtension.lowercased())
  }

  private func setMode(_ newMode: ArchiveMode) {
    mode = newMode
    modeControl.selectedSegment = newMode == .extract ? 0 : 1
    updateSelectionSummary()
  }

  private func updateSelectionSummary() {
    let text: String
    if selectedURLs.isEmpty {
      text = "还没有选择文件。"
    } else {
      text = selectedURLs.map { "• \($0.path)" }.joined(separator: "\n")
    }

    fileList.string = text
    let destinationText = destinationURL?.path ?? "自动"
    destinationLabel.stringValue = "输出位置：\(destinationText)"
    formatPopup.isEnabled = mode == .compress
    encryptHeaderButton.isEnabled = mode == .compress
    runButton.title = mode == .extract ? "解压" : "压缩"
  }

  private func appendLog(_ text: String) {
    logView.textStorage?.append(NSAttributedString(string: text))
    logView.scrollToEndOfDocument(nil)
  }

  private func showAlert(message: String, information: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = information
    alert.alertStyle = .informational
    alert.beginSheetModal(for: view.window ?? NSWindow())
  }

  private func buildUI() {
    let headerIcon = NSImageView()
    headerIcon.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: "7-Zip Mac")
    headerIcon.imageScaling = .scaleProportionallyUpOrDown

    let title = NSTextField(labelWithString: "7-Zip Mac")
    title.font = .systemFont(ofSize: 22, weight: .bold)

    let subtitle = NSTextField(labelWithString: "本地压缩与解压")
    subtitle.font = .systemFont(ofSize: 13)
    subtitle.textColor = .secondaryLabelColor

    let titleStack = NSStackView(views: [title, subtitle])
    titleStack.orientation = .vertical
    titleStack.alignment = .leading
    titleStack.spacing = 2

    let header = NSStackView(views: [headerIcon, titleStack])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 12

    modeControl.controlSize = .regular
    modeControl.segmentStyle = .rounded
    modeControl.setWidth(78, forSegment: 0)
    modeControl.setWidth(78, forSegment: 1)

    let addButton = button(title: "添加", symbol: "plus", action: #selector(addFiles))
    let destinationButton = button(title: "输出位置", symbol: "folder", action: #selector(chooseDestination))
    let clearButton = button(title: "清空", symbol: "xmark", action: #selector(clearFiles))

    let actionBar = NSStackView(views: [modeControl, addButton, destinationButton, clearButton])
    actionBar.orientation = .horizontal
    actionBar.alignment = .centerY
    actionBar.spacing = 8

    let topSpacer = NSView()
    topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let topBar = NSStackView(views: [header, topSpacer, actionBar])
    topBar.orientation = .horizontal
    topBar.alignment = .centerY
    topBar.spacing = 18

    fileList.isEditable = false
    fileList.isSelectable = true
    fileList.drawsBackground = false
    fileList.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    fileList.textColor = .secondaryLabelColor

    let fileScroll = NSScrollView()
    fileScroll.documentView = fileList
    fileScroll.hasVerticalScroller = true
    fileScroll.borderType = .noBorder
    fileScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true

    let filePanel = panel(title: "已选择", content: fileScroll)

    let formatLabel = NSTextField(labelWithString: "格式")
    let passwordLabel = NSTextField(labelWithString: "密码")
    let controlGrid = NSGridView(views: [
      [formatLabel, formatPopup],
      [passwordLabel, passwordField],
      [NSView(), encryptHeaderButton],
      [NSView(), destinationLabel]
    ])
    controlGrid.column(at: 0).xPlacement = .trailing
    controlGrid.column(at: 1).xPlacement = .fill
    controlGrid.rowSpacing = 10
    controlGrid.columnSpacing = 12
    formatPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
    passwordField.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true

    let optionsPanel = panel(title: "选项", content: controlGrid)

    logView.isEditable = false
    logView.isSelectable = true
    logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    logView.textColor = .labelColor
    logView.backgroundColor = .textBackgroundColor

    let logScroll = NSScrollView()
    logScroll.documentView = logView
    logScroll.hasVerticalScroller = true
    logScroll.borderType = .noBorder
    logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true

    let logPanel = panel(title: "任务日志", content: logScroll)

    runButton.bezelStyle = .rounded
    runButton.controlSize = .large
    runButton.keyEquivalent = "\r"
    runButton.widthAnchor.constraint(equalToConstant: 128).isActive = true

    let runBar = NSStackView(views: [NSView(), runButton])
    runBar.orientation = .horizontal
    runBar.alignment = .centerY
    runBar.spacing = 8

    let leftColumn = NSStackView(views: [dropZone, filePanel])
    leftColumn.orientation = .vertical
    leftColumn.alignment = .leading
    leftColumn.spacing = 14

    let rightColumn = NSStackView(views: [optionsPanel, logPanel, runBar])
    rightColumn.orientation = .vertical
    rightColumn.alignment = .leading
    rightColumn.spacing = 14

    let mainSplit = NSStackView(views: [leftColumn, rightColumn])
    mainSplit.orientation = .horizontal
    mainSplit.alignment = .top
    mainSplit.spacing = 16
    mainSplit.distribution = .fill

    let root = NSStackView(views: [topBar, mainSplit])
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 18
    root.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      root.topAnchor.constraint(equalTo: view.topAnchor, constant: 34),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22),
      headerIcon.widthAnchor.constraint(equalToConstant: 44),
      headerIcon.heightAnchor.constraint(equalToConstant: 44),
      topBar.widthAnchor.constraint(equalTo: root.widthAnchor),
      mainSplit.widthAnchor.constraint(equalTo: root.widthAnchor),
      mainSplit.heightAnchor.constraint(equalTo: root.heightAnchor, constant: -66),
      leftColumn.widthAnchor.constraint(equalTo: mainSplit.widthAnchor, multiplier: 0.58),
      rightColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
      dropZone.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
      filePanel.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
      optionsPanel.widthAnchor.constraint(equalTo: rightColumn.widthAnchor),
      logPanel.widthAnchor.constraint(equalTo: rightColumn.widthAnchor),
      runBar.widthAnchor.constraint(equalTo: rightColumn.widthAnchor)
    ])
  }

  private func button(title: String, symbol: String, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .rounded
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    button.imagePosition = .imageLeading
    return button
  }

  private func panel(title: String, content: NSView) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .secondaryLabelColor

    let stack = NSStackView(views: [label, content])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    let wrapper = RoundedPanelView()
    wrapper.fillColor = .controlBackgroundColor
    wrapper.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
      stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
      stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12),
      content.widthAnchor.constraint(equalTo: stack.widthAnchor)
    ])
    return wrapper
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  private let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1120, height: 630),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
  )

  private let controller = MainViewController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()

    window.center()
    window.title = "7-Zip Mac"
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.contentMinSize = NSSize(width: 960, height: 540)
    window.contentAspectRatio = NSSize(width: 16, height: 9)
    window.contentViewController = controller
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    controller.openArchivesAndExtract(urls: urls)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  @objc func compress7zSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    let urls = DropZoneView.fileURLs(from: pasteboard)
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入文件。"
      return
    }
    controller.prepareCompression(urls: urls, format: "7z", quitWhenFinished: true)
  }

  @objc func compressZipSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    let urls = DropZoneView.fileURLs(from: pasteboard)
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入文件。"
      return
    }
    controller.prepareCompression(urls: urls, format: "zip", quitWhenFinished: true)
  }

  @objc func extractHereSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    let urls = DropZoneView.fileURLs(from: pasteboard).filter { archiveExtensions.contains($0.pathExtension.lowercased()) }
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入支持的压缩包。"
      return
    }
    controller.prepareExtraction(
      urls: urls,
      destinationMode: .containingDirectory,
      quitWhenFinished: true,
      note: "Finder 服务：解压到当前文件夹。\n"
    )
  }

  @objc func extractToFolderSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    let urls = DropZoneView.fileURLs(from: pasteboard).filter { archiveExtensions.contains($0.pathExtension.lowercased()) }
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入支持的压缩包。"
      return
    }
    controller.prepareExtraction(
      urls: urls,
      destinationMode: .sameNameFolder,
      quitWhenFinished: true,
      note: "Finder 服务：解压到同名文件夹。\n"
    )
  }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
