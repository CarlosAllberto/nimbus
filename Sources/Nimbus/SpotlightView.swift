import SwiftUI

struct SpotlightView: View {
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var highlightedIndex = 0
    @FocusState private var isFieldFocused: Bool

    private var results: [NimbusTool] {
        guard !query.isEmpty else { return ToolCatalog.tools }
        return ToolCatalog.tools.filter { tool in
            tool.name.localizedCaseInsensitiveContains(query) ||
            tool.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            if !results.isEmpty {
                Divider()
                resultsList
            }
        }
        .frame(width: 560)
        .background(GlassBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .compositingGroup()
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, _ in highlightedIndex = 0 }
        .onExitCommand(perform: onCancel)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("Search Nimbus tools", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFieldFocused)
                .onKeyPress(.downArrow) { move(by: 1); return .handled }
                .onKeyPress(.upArrow) { move(by: -1); return .handled }
                .onKeyPress(.return) { activate(); return .handled }
        }
        .padding(16)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, tool in
                        SpotlightResultRow(tool: tool, isHighlighted: index == highlightedIndex)
                            .id(tool.id)
                            .onTapGesture { onSelect(tool.id) }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 360)
            .onChange(of: highlightedIndex) { _, newValue in
                guard results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(results[newValue].id, anchor: .center)
                }
            }
            .onChange(of: query) { _, _ in
                guard !results.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(results[0].id, anchor: .top)
                }
            }
        }
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        highlightedIndex = min(max(highlightedIndex + delta, 0), results.count - 1)
    }

    private func activate() {
        guard results.indices.contains(highlightedIndex) else { return }
        onSelect(results[highlightedIndex].id)
    }
}

private struct SpotlightResultRow: View {
    let tool: NimbusTool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(isHighlighted ? .white : .secondary)
            Text(tool.name)
                .font(.title3)
                .foregroundStyle(isHighlighted ? .white : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(isHighlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}