import SwiftUI
import AppKit
import MahdiCore

struct Session: Codable {
    var phase = "ready"
    var deadline: Date?
    var started: Date?
    var topic = ""
    var opening = ""
    var update = ""
    var closing = ""
    var noteID = UUID().uuidString
    var noteDate = Date()
    var lapID = UUID().uuidString
}

@MainActor final class Model: ObservableObject {
    @Published var s: Session
    @Published var now = Date()
    @Published var error = ""
    @Published var saved = ""
    @Published var vault: URL?
    var log: DailyLog? { vault.map { DailyLog(vault: $0) } }
    let configURL: URL
    let stateURL: URL
    var timer: Timer?
    var pending: Task<Void, Never>?
    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SecondBrainPomodoro")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stateURL = dir.appendingPathComponent("session.json")
        configURL = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL),
           let path = try? JSONDecoder().decode(String.self, from: data) {
            vault = URL(fileURLWithPath: path)
        }
        s = (try? JSONDecoder().decode(Session.self, from: Data(contentsOf: stateURL))) ?? Session()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
        if vault != nil { _ = flush() }
    }
    var remaining: Int { max(0, Int(ceil((s.deadline ?? now).timeIntervalSince(now)))) }
    var clock: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    func persist() {
        do { try JSONEncoder().encode(s).write(to: stateURL, options: .atomic) }
        catch { self.error = "Could not save session: \(error.localizedDescription)" }
    }
    @discardableResult func record(_ id: String, _ date: Date, _ text: String) -> Bool {
        guard let log, let vault, FileManager.default.fileExists(atPath: vault.path) else {
            error = "Choose an available Obsidian vault first."; return false
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = ""; return true }
        do { try log.write(id: id, date: date, text: text); error = ""; saved = "Saved to \(log.dateName(date))"; return true }
        catch { self.error = "Could not write daily note: \(error.localizedDescription)"; return false }
    }
    func start() {
        let date = Date(); s.lapID = UUID().uuidString
        guard record(s.lapID + "-start", date, s.opening) else { return }
        s.started = date; s.deadline = date.addingTimeInterval(25 * 60); s.phase = "focus"
        s.update = ""; s.closing = ""; s.noteID = UUID().uuidString; s.noteDate = date
        now = date; persist()
    }
    func tick() {
        now = Date()
        if let deadline = s.deadline, now >= deadline {
            if s.phase == "focus" { s.phase = "closing"; NSSound(named: "Glass")?.play(); NSApp.activate(ignoringOtherApps: true) }
            else if s.phase == "break" { s.phase = "ready"; s.opening = ""; NSSound(named: "Glass")?.play(); NSApp.activate(ignoringOtherApps: true) }
            s.deadline = nil; persist()
        }
    }
    func changed() {
        persist(); pending?.cancel()
        pending = Task { try? await Task.sleep(nanoseconds: 800_000_000); guard !Task.isCancelled else { return }; flush() }
    }
    @discardableResult func flush() -> Bool {
        guard !s.update.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return record(s.noteID, s.noteDate, s.update)
    }
    func newNote() {
        guard flush() else { return }; s.update = ""; s.noteID = UUID().uuidString; s.noteDate = Date(); persist()
    }
    func finish() { pending?.cancel(); _ = flush(); s.phase = "closing"; s.deadline = nil; persist() }
    func closeLap() {
        guard flush() else { return }
        let date = Date()
        guard record(s.lapID + "-end", date, s.closing) else { return }
        s.phase = "break"; s.deadline = date.addingTimeInterval(5 * 60); s.update = ""; s.noteID = UUID().uuidString; s.noteDate = date; now = date; persist()
    }
    func chooseVault() {
        guard s.phase == "ready" || vault == nil else {
            error = "Finish the lap and break before switching vaults."; return
        }
        let picker = NSOpenPanel()
        picker.title = "Choose your Obsidian vault"
        picker.prompt = "Connect vault"
        picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK, let selected = picker.url else { return }
        do {
            try JSONEncoder().encode(selected.path).write(to: configURL, options: .atomic)
            vault = selected; error = ""; saved = "Vault connected"
        } catch { self.error = "Could not save vault setting: \(error.localizedDescription)" }
    }
    func openDaily() {
        guard let log else { chooseVault(); return }
        let file = log.file(Date())
        if FileManager.default.fileExists(atPath: file.path) { NSWorkspace.shared.open(file) }
        else { error = "Today's note will be created when you log your first note." }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Model
    @State private var notes = false
    var title: String { m.s.phase == "focus" ? "focus" : m.s.phase == "break" ? "break" : m.s.phase == "closing" ? "lap done" : "ready" }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: m.s.phase == "focus" ? CGFloat(m.remaining) / 1500 : m.s.phase == "break" ? CGFloat(m.remaining) / 300 : 1)
                    .stroke(m.s.phase == "break" ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: m.s.phase == "break" ? "leaf" : "timer").font(.system(size: 15))
            }.frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.s.phase == "focus" || m.s.phase == "break" ? m.clock : m.s.phase == "ready" ? "25:00" : "00:00").font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                Text(m.error.isEmpty ? title : "save failed").font(.system(size: 10)).foregroundStyle(m.error.isEmpty ? Color.secondary : .red)
            }
            Spacer(minLength: 0)
            Button { notes.toggle() } label: { Image(systemName: m.s.phase == "ready" ? "play.fill" : "square.and.pencil").frame(width: 25, height: 30) }.buttonStyle(.plain).help("Open notes and lap controls")
                .popover(isPresented: $notes, arrowEdge: .top) { notePanel }
        }.padding(.horizontal, 16).frame(width: 240, height: 70)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onChange(of: m.s.phase) { _, phase in if phase == "closing" { notes = true } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in _ = m.flush(); m.persist() }
        .onChange(of: m.s.update) { _, _ in m.changed() }
        .onChange(of: m.s.opening) { _, _ in m.persist() }
        .onChange(of: m.s.closing) { _, _ in m.persist() }
    }
    var notePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.headline); Spacer(); Button { m.openDaily() } label: { Image(systemName: "book") }; Button { notes = false } label: { Image(systemName: "xmark") } }.buttonStyle(.plain)
            if m.vault == nil {
                Text("Connect your Obsidian vault to save lap notes.").font(.callout)
                Button("Choose vault…", action: m.chooseVault).buttonStyle(.borderedProminent)
            } else if m.s.phase == "ready" {
                editor("Starting note", text: $m.s.opening)
                Button("Start lap", action: { m.start(); if m.error.isEmpty { notes = false } }).buttonStyle(.borderedProminent)
            } else if m.s.phase == "focus" || m.s.phase == "closing" {
                editor("Note · autosaves", text: $m.s.update)
                HStack { Button("New note", action: m.newNote); Spacer(); if m.s.phase == "focus" { Button("Finish…", action: m.finish) } }
                if m.s.phase == "closing" {
                    editor("Closing note", text: $m.s.closing)
                    Button("Save & take 5", action: { m.closeLap(); if m.error.isEmpty { notes = false } }).buttonStyle(.borderedProminent)
                }
            } else { Text("Five minutes to breathe.").foregroundStyle(.secondary) }
            if !m.error.isEmpty { Text(m.error).font(.caption).foregroundStyle(.red); Button("Retry") { _ = m.flush() } }
            else if !m.saved.isEmpty { Text(m.saved).font(.caption2).foregroundStyle(.secondary) }
        }.padding(16).frame(width: 280)
    }
    func editor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); TextEditor(text: text).font(.system(size: 13)).frame(height: 70).padding(5).overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25))) }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor final class PanelHost: NSObject, NSApplicationDelegate {
    static var panel: NSPanel?
    static let model = Model()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 70), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Mahdi"
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ContentView().environmentObject(Self.model))
        if let screen = NSScreen.main { let frame = screen.visibleFrame; panel.setFrameOrigin(NSPoint(x: frame.maxX - 264, y: frame.minY + 16)) }
        Self.panel = panel; panel.orderFrontRegardless()
    }
    static func show() { panel?.orderFrontRegardless() }
    func applicationWillTerminate(_ notification: Notification) { _ = Self.model.flush(); Self.model.persist() }
}
@main struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(PanelHost.self) var delegate
    @StateObject var model = PanelHost.model
    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mahdi").font(.title2.bold())
                Text(model.vault?.path ?? "No vault connected").font(.caption).textSelection(.enabled)
                Button("Choose vault…", action: model.chooseVault).disabled(model.s.phase != "ready" && model.vault != nil)
                Text("Daily notes: datodine/YY·DDD.md").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 360)
        }
        MenuBarExtra {
            Button("Show Mahdi", action: PanelHost.show)
            Button("Daily note", action: model.openDaily)
            Button("Choose vault…", action: model.chooseVault).disabled(model.s.phase != "ready" && model.vault != nil)
            Divider()
            Button("Quit") { _ = model.flush(); model.persist(); NSApp.terminate(nil) }
        } label: { Text(model.s.phase == "focus" || model.s.phase == "break" ? "◷ \(model.clock)" : "◷ Mahdi") }
    }
}
