import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Model (same file format as the Android app, so backups are interchangeable)

struct Item: Identifiable, Codable, Equatable {
    var id: Int64
    var kind: String
    var title: String
    var body: String = ""
    var scope: String = "Month"
    var due: Int64 = 0
    var priority: Int = 1
    var target: Int = 10
    var current: Int = 0
    var done: Bool = false
    var pinned: Bool = false
    var days: String = ""
    var doneAt: Int64 = 0

    init(kind: String, title: String, due: Int64 = 0) {
        self.id = Int64(Date().timeIntervalSince1970 * 1000)
        self.kind = kind
        self.title = title
        self.due = due
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, scope, due, priority, target, current, done, pinned, days, doneAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "Month"
        due = try c.decodeIfPresent(Int64.self, forKey: .due) ?? 0
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        target = try c.decodeIfPresent(Int.self, forKey: .target) ?? 10
        current = try c.decodeIfPresent(Int.self, forKey: .current) ?? 0
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        days = try c.decodeIfPresent(String.self, forKey: .days) ?? ""
        doneAt = try c.decodeIfPresent(Int64.self, forKey: .doneAt) ?? 0
    }
}

final class Store: ObservableObject {
    @Published var items: [Item] = [] { didSet { save() } }
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyPlanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("items.json")
        if let d = try? Data(contentsOf: url), let l = try? JSONDecoder().decode([Item].self, from: d) {
            items = l
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: url, options: .atomic) }
    }

    func update(_ id: Int64, _ change: (inout Item) -> Void) {
        if let ix = items.firstIndex(where: { $0.id == id }) {
            var i = items[ix]
            change(&i)
            items[ix] = i
        }
    }

    func remove(_ id: Int64) { items.removeAll { $0.id == id } }

    func exportData() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        return try? e.encode(items)
    }

    func importData(_ d: Data) -> Bool {
        guard let l = try? JSONDecoder().decode([Item].self, from: d), !l.isEmpty else { return false }
        items = l
        return true
    }
}

// MARK: - Date helpers

func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
func msOf(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }
func dayStartMs() -> Int64 { msOf(Calendar.current.startOfDay(for: Date())) }

func endOfDayMs(_ d: Date) -> Int64 {
    let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: d) ?? d
    return msOf(end) + 999
}

func dayEndMs(_ plus: Int) -> Int64 {
    let base = Calendar.current.date(byAdding: .day, value: plus, to: Date()) ?? Date()
    return endOfDayMs(base)
}

func dayKey(_ offset: Int) -> String {
    let d = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd"
    return f.string(from: d)
}

func habitSet(_ s: String) -> Set<String> { Set(s.split(separator: ",").map { String($0) }) }

func streak(_ s: String) -> Int {
    let set = habitSet(s)
    var o = set.contains(dayKey(0)) ? 0 : -1
    var n = 0
    while set.contains(dayKey(o)) { n += 1; o -= 1 }
    return n
}

func dueText(_ ms: Int64) -> String {
    let f = DateFormatter()
    f.dateFormat = "EEE, d MMM"
    return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
}

func dayLetter(_ back: Int) -> String {
    let d = Calendar.current.date(byAdding: .day, value: -back, to: Date()) ?? Date()
    let f = DateFormatter()
    f.dateFormat = "EEEEE"
    return f.string(from: d)
}

// MARK: - App + desktop window

@main
struct PlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class DeskWindow: NSWindow {
    var dragStart: NSPoint?
    var dragOrigin: NSPoint = .zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            if !isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                makeKeyAndOrderFront(nil)
            }
            dragStart = e.locationInWindow.y > frame.height - 84 ? NSEvent.mouseLocation : nil
            dragOrigin = frame.origin
        case .leftMouseDragged:
            if let s = dragStart {
                let m = NSEvent.mouseLocation
                setFrameOrigin(NSPoint(x: dragOrigin.x + m.x - s.x, y: dragOrigin.y + m.y - s.y))
                return
            }
        case .leftMouseUp:
            dragStart = nil
        default:
            break
        }
        super.sendEvent(e)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: DeskWindow!
    var statusItem: NSStatusItem!
    let store = Store()
    var onTop = false
    let deskLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let w = DeskWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 540),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = deskLevel
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.contentView = NSHostingView(rootView: RootView().environmentObject(store))

        let restored = w.setFrameUsingName("PlannerPanel")
        if !restored, let s = NSScreen.main {
            w.setFrameOrigin(NSPoint(x: s.visibleFrame.maxX - 372, y: s.visibleFrame.maxY - 560))
        }
        w.setFrameAutosaveName("PlannerPanel")
        w.orderFrontRegardless()
        window = w

        if !UserDefaults.standard.bool(forKey: "loginAsked") {
            UserDefaults.standard.set(true, forKey: "loginAsked")
            try? SMAppService.mainApp.register()
        }
        setupStatusItem()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Planner")
        let m = NSMenu()
        m.addItem(withTitle: "Show Planner", action: #selector(showPanel), keyEquivalent: "")
        m.addItem(withTitle: "Hide Planner", action: #selector(hidePanel), keyEquivalent: "")
        let top = m.addItem(withTitle: "Keep Above Windows", action: #selector(toggleTop(_:)), keyEquivalent: "")
        top.state = .off
        m.addItem(.separator())
        let login = m.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(withTitle: "Back Up…", action: #selector(backup), keyEquivalent: "")
        m.addItem(withTitle: "Restore…", action: #selector(restore), keyEquivalent: "")
        m.addItem(.separator())
        let quit = m.addItem(withTitle: "Quit My Planner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in m.items where item !== quit { item.target = self }
        statusItem.menu = m
    }

    @objc func showPanel() { window.orderFrontRegardless() }
    @objc func hidePanel() { window.orderOut(nil) }

    @objc func toggleTop(_ sender: NSMenuItem) {
        onTop.toggle()
        sender.state = onTop ? .on : .off
        window.level = onTop ? .floating : deskLevel
        window.orderFrontRegardless()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister(); sender.state = .off }
            else { try s.register(); sender.state = .on }
        } catch {}
    }

    @objc func backup() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel()
        p.nameFieldStringValue = "planner-backup.json"
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let u = p.url, let d = store.exportData() { try? d.write(to: u) }
    }

    @objc func restore() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let u = p.url, let d = try? Data(contentsOf: u) { _ = store.importData(d) }
    }
}

// MARK: - Visuals

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct Ring: View {
    var progress: Double
    var label: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .frame(width: 54, height: 54)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .padding(.leading, 4)
    }
}

struct EmptyHint: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
    }
}

struct Page<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

struct RowCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Root

final class FocusModel: ObservableObject {
    @Published var total = 25 * 60
    @Published var left = 25 * 60
    @Published var running = false
    private var timer: Timer?

    func toggle() {
        if running { stop(); return }
        if left <= 0 { left = total }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop() { running = false; timer?.invalidate(); timer = nil }
    func reset() { stop(); left = total }
    func choose(_ minutes: Int) { stop(); total = minutes * 60; left = total }
    private func tick() {
        if left > 0 { left -= 1 }
        if left == 0 { stop(); NSSound.beep() }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @StateObject var focus = FocusModel()
    @State private var tab = 0
    @State private var draft = ""

    let icons = ["sun.max", "checklist", "target", "flame", "note.text", "timer"]
    let names = ["Today", "Tasks", "Goals", "Habits", "Notes", "Focus"]
    let kinds = ["task", "task", "goal", "habit", "note"]
    let placeholders = ["Add a task for today", "Add a task", "Add a goal", "Add a habit", "Write a note"]

    var ring: (Double, String)? {
        let s = dayStartMs(), e = dayEndMs(0)
        switch tab {
        case 0:
            let all = store.items.filter {
                $0.kind == "task" && (($0.due >= s && $0.due <= e) || (!$0.done && $0.due > 0 && $0.due < s))
            }
            let d = all.filter { $0.done }.count
            return (all.isEmpty ? 0 : Double(d) / Double(all.count), "\(d)/\(all.count)")
        case 1:
            let all = store.items.filter { $0.kind == "task" }
            let d = all.filter { $0.done }.count
            return (all.isEmpty ? 0 : Double(d) / Double(all.count), "\(d)/\(all.count)")
        case 2:
            let g = store.items.filter { $0.kind == "goal" }
            let avg = g.isEmpty ? 0 : g.map { $0.target > 0 ? min(1, Double($0.current) / Double($0.target)) : 0 }.reduce(0, +) / Double(g.count)
            return (avg, "\(Int(avg * 100))%")
        case 3:
            let h = store.items.filter { $0.kind == "habit" }
            let d = h.filter { habitSet($0.days).contains(dayKey(0)) }.count
            return (h.isEmpty ? 0 : Double(d) / Double(h.count), "\(d)/\(h.count)")
        case 4:
            return (0, "\(store.items.filter { $0.kind == "note" }.count)")
        default:
            return nil
        }
    }

    var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: Date()).uppercased()
    }

    var body: some View {
        ZStack {
            VisualEffect()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateString)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.secondary)
                        Text(names[tab])
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    if let r = ring { Ring(progress: r.0, label: r.1) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

                tabBar

                Group {
                    switch tab {
                    case 0: TodayView()
                    case 1: TasksView()
                    case 2: GoalsView()
                    case 3: HabitsView()
                    case 4: NotesView()
                    default: FocusView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if tab < 5 { addBar }
            }
        }
        .environmentObject(focus)
        .frame(width: 340, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<icons.count, id: \.self) { i in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tab = i }
                } label: {
                    Image(systemName: icons[i])
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(tab == i ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(tab == i ? Color.primary.opacity(0.13) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(names[i])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 16)
    }

    var addBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
            TextField(placeholders[tab], text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit { add() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
        .padding(16)
    }

    func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var it = Item(kind: kinds[tab], title: t, due: tab == 0 ? dayEndMs(0) : 0)
        if it.kind == "note" { it.body = t }
        store.items.insert(it, at: 0)
        draft = ""
    }
}

// MARK: - Tabs

struct TodayView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let s = dayStartMs()
        let e = dayEndMs(0)
        let tasks = store.items.filter { $0.kind == "task" }
        let overdue = tasks.filter { !$0.done && $0.due > 0 && $0.due < s }
        let todays = tasks.filter { $0.due >= s && $0.due <= e }
            .sorted { a, b in (!a.done && b.done) || (a.done == b.done && a.priority > b.priority) }
        let habits = store.items.filter { $0.kind == "habit" }
        Page {
            if !overdue.isEmpty {
                SectionLabel("Overdue")
                ForEach(overdue) { TaskRow(item: $0) }
            }
            SectionLabel("Today")
            if todays.isEmpty { EmptyHint("Nothing planned for today") }
            ForEach(todays) { TaskRow(item: $0) }
            if !habits.isEmpty {
                SectionLabel("Habits")
                ForEach(habits) { HabitRow(item: $0, compact: true) }
            }
        }
    }
}

struct TasksView: View {
    @EnvironmentObject var store: Store
    @State private var f = 0
    var body: some View {
        let list = store.items.filter { $0.kind == "task" && (f == 0 || (f == 1 && !$0.done) || (f == 2 && $0.done)) }
            .sorted { a, b in
                if a.done != b.done { return !a.done }
                if a.priority != b.priority { return a.priority > b.priority }
                return (a.due == 0 ? Int64.max : a.due) < (b.due == 0 ? Int64.max : b.due)
            }
        Page {
            Picker("", selection: $f) {
                Text("All").tag(0); Text("Pending").tag(1); Text("Done").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            if list.isEmpty { EmptyHint("No tasks here") }
            ForEach(list) { TaskRow(item: $0) }
        }
    }
}

struct GoalsView: View {
    @EnvironmentObject var store: Store
    @State private var f = 0
    let opts = ["All", "Week", "Month", "Year"]
    var body: some View {
        let list = store.items.filter { $0.kind == "goal" && (f == 0 || $0.scope == opts[f]) }
        Page {
            Picker("", selection: $f) {
                ForEach(0..<4, id: \.self) { Text(opts[$0]).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if list.isEmpty { EmptyHint("Set a week, month or year goal below") }
            ForEach(list) { GoalRow(item: $0) }
        }
    }
}

struct HabitsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let list = store.items.filter { $0.kind == "habit" }
        Page {
            if list.isEmpty { EmptyHint("Add a daily habit below") }
            ForEach(list) { HabitRow(item: $0, compact: false) }
        }
    }
}

struct NotesView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let list = store.items.filter { $0.kind == "note" }.sorted { $0.pinned && !$1.pinned }
        Page {
            if list.isEmpty { EmptyHint("Jot down ideas and things to remember") }
            ForEach(list) { NoteRow(item: $0) }
        }
    }
}

struct FocusView: View {
    @EnvironmentObject var focus: FocusModel
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(String(format: "%02d:%02d", focus.left / 60, focus.left % 60))
                .font(.system(size: 66, weight: .thin, design: .rounded))
                .monospacedDigit()
            ProgressView(value: 1 - Double(focus.left) / Double(max(focus.total, 1)))
                .padding(.horizontal, 40)
            HStack(spacing: 8) {
                ForEach([15, 25, 45], id: \.self) { m in
                    Button("\(m) min") { focus.choose(m) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(focus.total == m * 60 ? 0.16 : 0.06)))
                }
            }
            HStack(spacing: 10) {
                Button(focus.running ? "Pause" : "Start") { focus.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(Capsule().fill(Color.accentColor))
                Button("Reset") { focus.reset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rows

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let item: Item
    @State private var showPick = false
    @State private var pickDate = Date()

    var body: some View {
        let late = !item.done && item.due > 0 && item.due < dayStartMs()
        RowCard {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    store.update(item.id) { $0.done.toggle(); $0.doneAt = $0.done ? nowMs() : 0 }
                } label: {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    if item.due > 0 {
                        Text((late ? "Overdue · " : "") + dueText(item.due))
                            .font(.system(size: 11))
                            .foregroundStyle(late ? Color.red : Color.secondary)
                    }
                }
                Spacer(minLength: 4)
                if item.priority == 2 {
                    Image(systemName: "flag.fill").font(.system(size: 11)).foregroundStyle(Color.red)
                }
                Menu {
                    Menu("Priority") {
                        Button("Low") { store.update(item.id) { $0.priority = 0 } }
                        Button("Medium") { store.update(item.id) { $0.priority = 1 } }
                        Button("High") { store.update(item.id) { $0.priority = 2 } }
                    }
                    Menu("Deadline") {
                        Button("None") { store.update(item.id) { $0.due = 0 } }
                        Button("Today") { store.update(item.id) { $0.due = dayEndMs(0) } }
                        Button("Tomorrow") { store.update(item.id) { $0.due = dayEndMs(1) } }
                        Button("In a week") { store.update(item.id) { $0.due = dayEndMs(7) } }
                        Button("Pick date…") {
                            pickDate = item.due > 0 ? Date(timeIntervalSince1970: Double(item.due) / 1000) : Date()
                            showPick = true
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { store.remove(item.id) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
            }
        }
        .popover(isPresented: $showPick) {
            DatePicker("", selection: $pickDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
                .onChange(of: pickDate) { d in
                    store.update(item.id) { $0.due = endOfDayMs(d) }
                    showPick = false
                }
        }
    }
}

struct GoalRow: View {
    @EnvironmentObject var store: Store
    let item: Item

    var body: some View {
        let p = item.target > 0 ? min(1, Double(item.current) / Double(item.target)) : 0
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.scope.uppercased() + " GOAL")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.accentColor)
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                    }
                    Spacer()
                    Text("\(Int(p * 100))%")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Menu {
                        Menu("Period") {
                            Button("Week") { store.update(item.id) { $0.scope = "Week" } }
                            Button("Month") { store.update(item.id) { $0.scope = "Month" } }
                            Button("Year") { store.update(item.id) { $0.scope = "Year" } }
                        }
                        Menu("Target") {
                            ForEach([5, 10, 20, 30, 50, 100, 365], id: \.self) { n in
                                Button("Target \(n)") { store.update(item.id) { $0.target = n } }
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { store.remove(item.id) }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Color.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22)
                }
                ProgressView(value: p)
                HStack {
                    Text("\(item.current) of \(item.target)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    stepper("minus") { store.update(item.id) { $0.current = max(0, $0.current - 1) } }
                    stepper("plus") { store.update(item.id) { $0.current += 1 } }
                }
            }
        }
    }

    func stepper(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

struct HabitRow: View {
    @EnvironmentObject var store: Store
    let item: Item
    let compact: Bool

    var body: some View {
        let set = habitSet(item.days)
        let today = dayKey(0)
        let doneToday = set.contains(today)
        RowCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        Label("\(streak(item.days)) day streak", systemImage: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Button {
                        store.update(item.id) { i in
                            var s = habitSet(i.days)
                            if s.contains(today) { s.remove(today) } else { s.insert(today) }
                            i.days = s.sorted().joined(separator: ",")
                        }
                    } label: {
                        Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(doneToday ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    if !compact {
                        Menu {
                            Button("Delete", role: .destructive) { store.remove(item.id) }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(Color.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 22)
                    }
                }
                if !compact {
                    HStack(spacing: 0) {
                        ForEach((0..<7).reversed(), id: \.self) { b in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(set.contains(dayKey(-b)) ? Color.accentColor : Color.primary.opacity(0.12))
                                    .frame(width: 10, height: 10)
                                Text(dayLetter(b)).font(.system(size: 9)).foregroundStyle(Color.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

struct NoteRow: View {
    @EnvironmentObject var store: Store
    let item: Item

    var body: some View {
        RowCard {
            HStack(alignment: .top, spacing: 8) {
                TextField("Note", text: Binding(
                    get: { item.body.isEmpty ? item.title : item.body },
                    set: { v in
                        store.update(item.id) {
                            $0.body = v
                            $0.title = String((v.split(separator: "\n").first ?? "").prefix(40))
                        }
                    }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...8)

                VStack(spacing: 8) {
                    Button {
                        store.update(item.id) { $0.pinned.toggle() }
                    } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        store.remove(item.id)
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
