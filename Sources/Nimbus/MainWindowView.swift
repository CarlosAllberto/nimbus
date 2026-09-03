import SwiftUI

struct MainWindowView: View {
    @State private var query = ""
    @State private var selectedToolID = ToolCatalog.tools[0].id
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var isSearchFocused: Bool
    @ObservedObject private var spotlightNavigator = SpotlightNavigator.shared
    @ObservedObject private var auth = AuthSession.shared
    @ObservedObject private var updateIndicator = UpdateIndicator.shared
    @Environment(\.openWindow) private var openWindow

    private var filteredTools: [NimbusTool] {
        guard !query.isEmpty else { return ToolCatalog.tools }
        return ToolCatalog.tools.filter { tool in
            tool.name.localizedCaseInsensitiveContains(query) ||
            tool.summary.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedTool: NimbusTool {
        ToolCatalog.tools.first { $0.id == selectedToolID } ?? ToolCatalog.tools[0]
    }

    var body: some View {
        // Nimbus requires an account: without a live session the whole window
        // is the sign-in gate, not just a disabled action button. The catalog
        // below is reached only in `.signedIn`.
        Group {
            if case .signedIn = auth.state {
                catalog
            } else {
                AuthGateView()
            }
        }
    }

    private var catalog: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                SidebarSearchField(query: $query, isFocused: $isSearchFocused)
                ScrollViewReader { proxy in
                    List(selection: $selectedToolID) {
                        ForEach(ToolGroup.allCases) { group in
                            let tools = filteredTools.filter { $0.group == group }
                            if !tools.isEmpty {
                                Section {
                                    ForEach(tools) { tool in
                                        Label(tool.name, systemImage: tool.icon)
                                            .id(tool.id)
                                            .tag(tool.id)
                                            .accessibilityLabel(tool.name)
                                    }
                                } header: {
                                    Text(group.title)
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: spotlightNavigator.pendingToolID) { _, newValue in
                        guard let newValue else { return }
                        selectedToolID = newValue
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                        _ = spotlightNavigator.consumePendingToolID()
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            ToolDetailView(tool: selectedTool, isSidebarVisible: columnVisibility != .detailOnly)
                .id(selectedTool.id)
        }
        // A floating badge, not a toolbar item: two attempts at getting a
        // custom item to sit beside NavigationSplitView's automatic sidebar
        // toggle both failed on macOS — the native toggle carries a
        // sidebar-width layout alignment a hand-rolled replacement doesn't
        // inherit, so removing it left every `.navigation` item unmoored
        // from the sidebar's actual width, floating over the detail title
        // instead. This sidesteps NSToolbar entirely.
        .overlay(alignment: .topTrailing) {
            if let info = updateIndicator.available {
                Button {
                    NSWorkspace.shared.open(UpdateChecker.releasePageURL)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .padding(10)
                .help("Update available (build \(info.build)) — click to download")
            }
        }
        .background {
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        // Capture the `openWindow` action so `AppDelegate.showMainWindow()`
        // can reopen the main window via the documented SwiftUI path
        // (`Window(id:)` is a singleton -- once closed, the only way back in
        // is `openWindow(id:)`). Registered fresh each time the View comes
        // back, cleared on disappear so a stale capture can never fire while
        // the window is gone.
        .onAppear {
            MainWindowOpener.shared.registerOpenAction { [openWindow] in
                openWindow(id: "main")
            }
        }
        .onDisappear {
            // Drop the capture so the action can never fire against a
            // closed-and-not-rebuilt window. `onAppear` will re-register
            // when SwiftUI rebuilds the View on reopen.
            MainWindowOpener.shared.registerOpenAction { }
        }
    }
}

private struct SidebarSearchField: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search tools", text: $query)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .accessibilityLabel("Search tools")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.secondary.opacity(0.16), in: Capsule())
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

private struct ToolDetailView: View {
    let tool: NimbusTool
    let isSidebarVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let configuration = FileToolConfiguration.configuration(for: tool.id) {
                FileToolView(
                    tool: tool,
                    configuration: configuration,
                    isSidebarVisible: isSidebarVisible
                )
            } else if let configuration = FormToolConfiguration.configuration(for: tool.id) {
                FormToolView(tool: tool, configuration: configuration, isSidebarVisible: isSidebarVisible)
            } else if let kind = NativeToolKind(rawValue: tool.id) {
                NativeToolView(kind: kind, tool: tool, isSidebarVisible: isSidebarVisible)
            } else {
                GenericToolView(tool: tool)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct GenericToolView: View {
    let tool: NimbusTool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: tool.icon)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(tool.name)
                .font(.title.bold())
            Text(tool.summary)
                .foregroundStyle(.secondary)
            Button("Open Tool") { }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainWindowView()
}
