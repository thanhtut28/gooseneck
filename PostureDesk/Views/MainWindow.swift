import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .history: "chart.bar"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct MainWindow: View {
    @Environment(PostureViewModel.self) private var viewModel
    @State private var selection: SidebarItem = .dashboard
    @Namespace private var sidebarNS

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 2) {
                ForEach(SidebarItem.allCases) { item in
                    sidebarButton(item)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        } detail: {
            Group {
                switch selection {
                case .dashboard:
                    DashboardView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Colors.bg)
        }
        .preferredColorScheme(viewModel.preferredColorScheme)
    }

    private func sidebarButton(_ item: SidebarItem) -> some View {
        let isSelected = selection == item

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selection = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20)
                Text(item.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))
                Spacer()
            }
            .foregroundStyle(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "sidebarPill", in: sidebarNS)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursorModifier(enabled: !isSelected))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let enabled: Bool
    @State private var isCursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard enabled else {
                    if isCursorPushed {
                        NSCursor.pop()
                        isCursorPushed = false
                    }
                    return
                }

                guard hovering != isCursorPushed else { return }

                if hovering {
                    NSCursor.pointingHand.push()
                    isCursorPushed = true
                } else {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
            .onDisappear {
                if isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
    }
}
