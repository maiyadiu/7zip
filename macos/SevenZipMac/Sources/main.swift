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

private enum CompressionProfile {
  case sevenZipDefault
  case sevenZipUltra
  case zipDefault

  var format: String {
    switch self {
    case .sevenZipDefault, .sevenZipUltra:
      return "7z"
    case .zipDefault:
      return "zip"
    }
  }

  var serviceLabel: String {
    switch self {
    case .sevenZipDefault:
      return "7z"
    case .sevenZipUltra:
      return "极限 7z"
    case .zipDefault:
      return "zip"
    }
  }

  var compressionArguments: [String] {
    switch self {
    case .sevenZipDefault:
      return []
    case .sevenZipUltra:
      return ["-mx=9", "-m0=LZMA2", "-md=256m", "-mfb=273", "-ms=on", "-mmt=on"]
    case .zipDefault:
      return ["-mx=9"]
    }
  }

  static func from(format: String) -> CompressionProfile {
    format == "zip" ? .zipDefault : .sevenZipDefault
  }
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

  @discardableResult
  func run(
    arguments: [String],
    workingDirectory: URL?,
    output: @escaping (String) -> Void,
    completion: @escaping (Int32) -> Void
  ) -> Process? {
    let process = Process()
    let pipe = Pipe()
    let input = Pipe()

    process.executableURL = engineURL
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.standardInput = input
    process.standardOutput = pipe
    process.standardError = pipe
    input.fileHandleForWriting.closeFile()

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
      return process
    } catch {
      pipe.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async {
        output("启动 7zz 失败：\(error.localizedDescription)\n")
        completion(1)
      }
      return nil
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

private struct ArchiveEntry {
  let archiveName: String
  let path: String
  let size: String
  let modified: String
  let kind: String
}

private final class ArchiveEntryStore: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  var entries: [ArchiveEntry] = []

  func numberOfRows(in tableView: NSTableView) -> Int {
    entries.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < entries.count, let tableColumn else { return nil }
    let id = tableColumn.identifier
    let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(identifier: id)
    let entry = entries[row]

    switch id.rawValue {
    case "archive":
      cell.textField?.stringValue = entry.archiveName
    case "size":
      cell.textField?.stringValue = entry.size
    case "modified":
      cell.textField?.stringValue = entry.modified
    case "kind":
      cell.textField?.stringValue = entry.kind
    default:
      cell.textField?.stringValue = entry.path
    }

    return cell
  }

  private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let textField = NSTextField(labelWithString: "")
    textField.lineBreakMode = .byTruncatingMiddle
    textField.font = .systemFont(ofSize: 12)
    textField.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(textField)
    cell.textField = textField
    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
      textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
      textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
    ])
    return cell
  }
}

private enum ArchiveListingParser {
  static func parse(_ output: String, archive: URL) -> [ArchiveEntry] {
    var records: [[String: String]] = []
    var current: [String: String] = [:]

    for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else {
        if !current.isEmpty {
          records.append(current)
          current = [:]
        }
        continue
      }

      guard let separator = line.firstIndex(of: "=") else { continue }
      let key = line[..<separator].trimmingCharacters(in: .whitespaces)
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      current[key] = value
    }

    if !current.isEmpty {
      records.append(current)
    }

    return records.compactMap { record in
      guard let path = record["Path"], !path.isEmpty else { return nil }
      if path == archive.path || path == archive.lastPathComponent {
        return nil
      }
      if record["Type"] != nil, record["Size"] == nil {
        return nil
      }

      let isDirectory = record["Folder"] == "+" || (record["Attributes"] ?? "").contains("D")
      return ArchiveEntry(
        archiveName: archive.lastPathComponent,
        path: path,
        size: isDirectory ? "" : formatByteString(record["Size"]),
        modified: record["Modified"] ?? "",
        kind: isDirectory ? "文件夹" : "文件"
      )
    }
  }

  private static func formatByteString(_ value: String?) -> String {
    guard let value, let bytes = Int64(value) else { return value ?? "" }
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

private final class ExtractionProgressWindowController: NSWindowController, NSWindowDelegate {
  private let archives: [URL]
  private var queue: [URL]
  private var currentProcess: Process?
  private var completedCount = 0
  private var failedCount = 0
  private var didFinish = false
  private var didCancel = false

  private let titleLabel = NSTextField(labelWithString: "正在解压")
  private let detailLabel = NSTextField(labelWithString: "")
  private let progress = NSProgressIndicator()
  private let statusLabel = NSTextField(labelWithString: "")
  private let actionButton = NSButton(title: "取消", target: nil, action: nil)

  init(archives: [URL]) {
    self.archives = archives
    self.queue = archives

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 178),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "7-Zip Mac"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    buildUI()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func start() {
    window?.center()
    showWindow(nil)
    runNext()
  }

  func windowWillClose(_ notification: Notification) {
    if !didFinish {
      currentProcess?.terminate()
    }
    NSApp.terminate(nil)
  }

  @objc private func actionButtonPressed() {
    if didFinish {
      close()
      return
    }

    didCancel = true
    currentProcess?.terminate()
    queue.removeAll()
    failedCount += 1
    complete(message: "已取消。", shouldAutoClose: false)
  }

  private func buildUI() {
    guard let contentView = window?.contentView else { return }

    let icon = NSImageView()
    icon.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: "7-Zip Mac")
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    detailLabel.font = .systemFont(ofSize: 13)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingMiddle

    progress.isIndeterminate = false
    progress.minValue = 0
    progress.maxValue = Double(max(archives.count, 1))
    progress.doubleValue = 0
    progress.controlSize = .regular

    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.lineBreakMode = .byTruncatingTail

    actionButton.target = self
    actionButton.action = #selector(actionButtonPressed)
    actionButton.bezelStyle = .rounded

    let textStack = NSStackView(views: [titleLabel, detailLabel, progress, statusLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 8
    textStack.translatesAutoresizingMaskIntoConstraints = false

    let body = NSStackView(views: [icon, textStack])
    body.orientation = .horizontal
    body.alignment = .top
    body.spacing = 14
    body.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(body)
    contentView.addSubview(actionButton)
    actionButton.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      body.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      body.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      body.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
      icon.widthAnchor.constraint(equalToConstant: 44),
      icon.heightAnchor.constraint(equalToConstant: 44),
      textStack.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -58),
      progress.widthAnchor.constraint(equalTo: textStack.widthAnchor),
      actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
      actionButton.widthAnchor.constraint(equalToConstant: 88)
    ])
  }

  private func runNext() {
    guard !queue.isEmpty else {
      let message = failedCount == 0 ? "解压完成。" : "完成，\(failedCount) 个压缩包失败。"
      complete(message: message, shouldAutoClose: failedCount == 0)
      return
    }

    let archive = queue.removeFirst()
    let output = archive.deletingLastPathComponent()
    detailLabel.stringValue = archive.lastPathComponent
    statusLabel.stringValue = "输出位置：\(output.path)"

    let args = ["x", archive.path, "-o\(output.path)", "-y", "-aou"]
    do {
      let runner = try ArchiveTaskRunner()
      currentProcess = runner.run(arguments: args, workingDirectory: output, output: { [weak self] text in
        self?.consumeProgressOutput(text)
      }, completion: { [weak self] status in
        guard let self else { return }
        guard !self.didCancel else { return }
        self.currentProcess = nil
        self.completedCount += 1
        if status != 0 {
          self.failedCount += 1
        }
        self.progress.doubleValue = Double(self.completedCount)
        self.runNext()
      })
    } catch {
      failedCount += 1
      completedCount += 1
      progress.doubleValue = Double(completedCount)
      statusLabel.stringValue = error.localizedDescription
      runNext()
    }
  }

  private func consumeProgressOutput(_ text: String) {
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    if let line = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
      statusLabel.stringValue = line
    }
  }

  private func complete(message: String, shouldAutoClose: Bool) {
    didFinish = true
    currentProcess = nil
    titleLabel.stringValue = failedCount == 0 ? "解压完成" : "解压未全部完成"
    detailLabel.stringValue = message
    statusLabel.stringValue = failedCount == 0 ? "文件已解压到压缩包所在文件夹。" : "请用主界面查看日志或输入密码后重试。"
    progress.doubleValue = progress.maxValue
    actionButton.title = "关闭"

    if shouldAutoClose {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
        self?.close()
      }
    }
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
  private let contentTable = NSTableView()
  private let contentStatusLabel = NSTextField(labelWithString: "还没有读取压缩包内容。")
  private let archiveEntryStore = ArchiveEntryStore()
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
      revealWhenFinished: false,
      note: "双击打开：自动解压到压缩包所在文件夹。\n"
    )
  }

  func previewArchives(urls: [URL]) {
    let archives = urls.filter { Self.isArchive($0) }
    guard !archives.isEmpty else {
      accept(urls: urls)
      return
    }

    selectedURLs = archives
    setMode(.extract)
    destinationURL = nil
    updateSelectionSummary()
    archiveEntryStore.entries = []
    contentTable.reloadData()
    contentStatusLabel.stringValue = "正在读取压缩包内容..."
    replaceLog("正在读取压缩包内容...\n")
    listArchiveContents(archives)
  }

  func prepareExtraction(
    urls: [URL],
    destinationMode: ExtractionDestinationMode,
    quitWhenFinished: Bool,
    revealWhenFinished: Bool,
    note: String? = nil
  ) {
    selectedURLs = urls.filter { Self.isArchive($0) }
    setMode(.extract)
    destinationURL = nil
    updateSelectionSummary()
    if let note {
      appendLog(note)
    }
    startExtract(
      destinationMode: destinationMode,
      quitWhenFinished: quitWhenFinished,
      revealWhenFinished: revealWhenFinished
    )
  }

  func prepareCompression(urls: [URL], profile: CompressionProfile, quitWhenFinished: Bool, revealWhenFinished: Bool) {
    selectedURLs = urls
    setMode(.compress)
    destinationURL = nil
    formatPopup.selectItem(withTitle: profile.format)
    updateSelectionSummary()
    appendLog("Finder 服务：压缩为 \(profile.serviceLabel)。\n")
    startCompress(profile: profile, quitWhenFinished: quitWhenFinished, revealWhenFinished: revealWhenFinished)
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
      startExtract(destinationMode: .sameNameFolder, quitWhenFinished: false, revealWhenFinished: false)
    case .compress:
      let profile = CompressionProfile.from(format: formatPopup.titleOfSelectedItem ?? "7z")
      startCompress(profile: profile, quitWhenFinished: false, revealWhenFinished: false)
    }
  }

  private func startExtract(destinationMode: ExtractionDestinationMode, quitWhenFinished: Bool, revealWhenFinished: Bool) {
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
        finishRun(revealURLs: outputURLs, quitWhenFinished: quitWhenFinished, revealWhenFinished: revealWhenFinished)
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

  private func startCompress(profile: CompressionProfile, quitWhenFinished: Bool, revealWhenFinished: Bool) {
    let format = profile.format
    guard let output = archiveOutputURL(format: format) else {
      showAlert(message: "无法确定压缩包名称", information: "请选择位于可写目录中的文件或文件夹。")
      return
    }

    runButton.isEnabled = false
    isRunning = true

    let workingDirectory = commonDirectory(for: selectedURLs)
    let paths = selectedURLs.map { relativePath(for: $0, from: workingDirectory) }
    var args = ["a", output.path, "-t\(format)"]
    args.append(contentsOf: profile.compressionArguments)

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
      self?.finishRun(
        revealURLs: status == 0 ? [output] : [],
        quitWhenFinished: quitWhenFinished,
        revealWhenFinished: revealWhenFinished
      )
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

  private func run7zzCapturing(
    arguments: [String],
    workingDirectory: URL?,
    completion: @escaping (Int32, String) -> Void
  ) {
    do {
      let runner = try ArchiveTaskRunner()
      var captured = ""
      runner.run(arguments: arguments, workingDirectory: workingDirectory, output: { text in
        captured += text
      }, completion: { status in
        completion(status, captured)
      })
    } catch {
      completion(1, "\(error.localizedDescription)\n")
    }
  }

  private func listArchiveContents(_ archives: [URL]) {
    var queue = archives
    var allEntries: [ArchiveEntry] = []

    func runNext() {
      guard !queue.isEmpty else {
        archiveEntryStore.entries = allEntries
        contentTable.reloadData()
        contentStatusLabel.stringValue = allEntries.isEmpty ? "没有读取到文件条目。" : "已读取 \(allEntries.count) 个条目。"
        appendLog("内容读取完成，共 \(allEntries.count) 个条目。\n")
        return
      }

      let archive = queue.removeFirst()
      appendLog("\n压缩包：\(archive.lastPathComponent)\n")
      appendLog("路径：\(archive.path)\n\n")
      var args = ["l", "-slt", archive.path]
      let password = passwordField.stringValue
      if !password.isEmpty {
        args.append("-p\(password)")
      }
      run7zzCapturing(arguments: args, workingDirectory: archive.deletingLastPathComponent()) { [weak self] status, output in
        guard let self else { return }
        if status == 0 {
          let entries = ArchiveListingParser.parse(output, archive: archive)
          allEntries.append(contentsOf: entries)
          self.appendLog("读取成功：\(archive.lastPathComponent)，\(entries.count) 个条目。\n")
        } else {
          self.appendLog("读取失败：\(archive.lastPathComponent)，退出码=\(status)\n")
          self.appendLog(output)
        }
        runNext()
      }
    }

    runNext()
  }

  private func finishRun(revealURLs: [URL], quitWhenFinished: Bool, revealWhenFinished: Bool) {
    isRunning = false
    runButton.isEnabled = true
    appendLog("全部任务已完成。\n")
    if revealWhenFinished, !revealURLs.isEmpty {
      NSWorkspace.shared.activateFileViewerSelecting(revealURLs)
    }
    if quitWhenFinished {
      NSApp.terminate(nil)
    }
  }

  private func extractionArguments(archive: URL, output: URL) -> [String] {
    var args = ["x", archive.path, "-o\(output.path)", "-y", "-aou"]
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

  private func replaceLog(_ text: String) {
    logView.string = text
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

    configureArchiveContentTable()
    let contentScroll = NSScrollView()
    contentScroll.documentView = contentTable
    contentScroll.hasVerticalScroller = true
    contentScroll.hasHorizontalScroller = true
    contentScroll.autohidesScrollers = true
    contentScroll.borderType = .noBorder

    contentStatusLabel.font = .systemFont(ofSize: 12)
    contentStatusLabel.textColor = .secondaryLabelColor
    let contentStack = NSStackView(views: [contentStatusLabel, contentScroll])
    contentStack.orientation = .vertical
    contentStack.alignment = .leading
    contentStack.spacing = 6
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    let contentContainer = NSView()
    contentContainer.addSubview(contentStack)
    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 8),
      contentStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8),
      contentStack.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 8),
      contentStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8)
    ])

    logView.isEditable = false
    logView.isSelectable = true
    logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    logView.textColor = .labelColor
    logView.backgroundColor = .textBackgroundColor

    let logScroll = NSScrollView()
    logScroll.documentView = logView
    logScroll.hasVerticalScroller = true
    logScroll.borderType = .noBorder
    logScroll.translatesAutoresizingMaskIntoConstraints = false
    let logContainer = NSView()
    logContainer.addSubview(logScroll)
    NSLayoutConstraint.activate([
      logScroll.leadingAnchor.constraint(equalTo: logContainer.leadingAnchor, constant: 8),
      logScroll.trailingAnchor.constraint(equalTo: logContainer.trailingAnchor, constant: -8),
      logScroll.topAnchor.constraint(equalTo: logContainer.topAnchor, constant: 8),
      logScroll.bottomAnchor.constraint(equalTo: logContainer.bottomAnchor, constant: -8)
    ])

    let detailTabs = NSTabView()
    detailTabs.tabViewType = .topTabsBezelBorder
    let contentTab = NSTabViewItem(identifier: "contents")
    contentTab.label = "压缩包内容"
    contentTab.view = contentContainer
    let logTab = NSTabViewItem(identifier: "log")
    logTab.label = "任务日志"
    logTab.view = logContainer
    detailTabs.addTabViewItem(contentTab)
    detailTabs.addTabViewItem(logTab)
    detailTabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true

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

    let rightColumn = NSStackView(views: [optionsPanel, detailTabs, runBar])
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
      detailTabs.widthAnchor.constraint(equalTo: rightColumn.widthAnchor),
      runBar.widthAnchor.constraint(equalTo: rightColumn.widthAnchor)
    ])
  }

  private func configureArchiveContentTable() {
    guard contentTable.tableColumns.isEmpty else { return }

    let columns: [(String, String, CGFloat)] = [
      ("path", "名称", 280),
      ("size", "大小", 82),
      ("modified", "修改时间", 138),
      ("kind", "类型", 64),
      ("archive", "压缩包", 140)
    ]

    for (identifier, title, width) in columns {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
      column.title = title
      column.width = width
      column.minWidth = identifier == "path" ? 180 : 54
      contentTable.addTableColumn(column)
    }

    contentTable.delegate = archiveEntryStore
    contentTable.dataSource = archiveEntryStore
    contentTable.usesAlternatingRowBackgroundColors = true
    contentTable.headerView = NSTableHeaderView()
    contentTable.rowHeight = 24
    contentTable.allowsMultipleSelection = true
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
  private var progressWindowController: ExtractionProgressWindowController?
  private var didReceiveBackgroundAction = false
  private var didConfigureWindow = false
  private var showWindowWorkItem: DispatchWorkItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()
    scheduleInitialWindowDisplay()
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    let archives = urls.filter { archiveExtensions.contains($0.pathExtension.lowercased()) }
    guard !archives.isEmpty else {
      showMainWindow()
      controller.accept(urls: urls)
      return
    }

    suppressInitialWindow()
    showExtractionProgress(for: archives)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func scheduleInitialWindowDisplay() {
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, !self.didReceiveBackgroundAction else { return }
      self.showMainWindow()
    }
    showWindowWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
  }

  private func suppressInitialWindow() {
    didReceiveBackgroundAction = true
    showWindowWorkItem?.cancel()
  }

  private func beginBackgroundAction() {
    suppressInitialWindow()
    _ = controller.view
  }

  private func configureWindowIfNeeded() {
    guard !didConfigureWindow else { return }
    window.center()
    window.title = "7-Zip Mac"
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.contentMinSize = NSSize(width: 960, height: 540)
    window.contentAspectRatio = NSSize(width: 16, height: 9)
    window.contentViewController = controller
    didConfigureWindow = true
  }

  private func showMainWindow() {
    configureWindowIfNeeded()
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showExtractionProgress(for archives: [URL]) {
    let progressWindowController = ExtractionProgressWindowController(archives: archives)
    self.progressWindowController = progressWindowController
    NSApp.setActivationPolicy(.regular)
    progressWindowController.start()
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc func compress7zSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    beginBackgroundAction()
    let urls = DropZoneView.fileURLs(from: pasteboard)
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入文件。"
      return
    }
    controller.prepareCompression(urls: urls, profile: .sevenZipDefault, quitWhenFinished: true, revealWhenFinished: false)
  }

  @objc func compressUltra7zSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    beginBackgroundAction()
    let urls = DropZoneView.fileURLs(from: pasteboard)
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入文件。"
      return
    }
    controller.prepareCompression(urls: urls, profile: .sevenZipUltra, quitWhenFinished: true, revealWhenFinished: false)
  }

  @objc func compressZipSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    beginBackgroundAction()
    let urls = DropZoneView.fileURLs(from: pasteboard)
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入文件。"
      return
    }
    controller.prepareCompression(urls: urls, profile: .zipDefault, quitWhenFinished: true, revealWhenFinished: false)
  }

  @objc func extractHereSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    beginBackgroundAction()
    let urls = DropZoneView.fileURLs(from: pasteboard).filter { archiveExtensions.contains($0.pathExtension.lowercased()) }
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入支持的压缩包。"
      return
    }
    controller.prepareExtraction(
      urls: urls,
      destinationMode: .containingDirectory,
      quitWhenFinished: true,
      revealWhenFinished: false,
      note: "Finder 服务：解压到当前文件夹。\n"
    )
  }

  @objc func extractToFolderSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    beginBackgroundAction()
    let urls = DropZoneView.fileURLs(from: pasteboard).filter { archiveExtensions.contains($0.pathExtension.lowercased()) }
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入支持的压缩包。"
      return
    }
    controller.prepareExtraction(
      urls: urls,
      destinationMode: .sameNameFolder,
      quitWhenFinished: true,
      revealWhenFinished: false,
      note: "Finder 服务：解压到同名文件夹。\n"
    )
  }

  @objc func previewArchiveSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    let urls = DropZoneView.fileURLs(from: pasteboard).filter { archiveExtensions.contains($0.pathExtension.lowercased()) }
    guard !urls.isEmpty else {
      error.pointee = "Finder 没有传入支持的压缩包。"
      return
    }
    showMainWindow()
    controller.previewArchives(urls: urls)
  }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
