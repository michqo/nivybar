//
//  ContentView.swift
//  NivyBar
//

import SwiftUI

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject private var vm: MenuViewModel
    @Environment(\.openWindow) private var openWindow

    // Hardcoded restaurants always have displayOrder < 0
    private var hardcodedMenus: [RestaurantMenu] { vm.menus.filter { $0.displayOrder < 0 } }
    private var userMenus: [RestaurantMenu]      { vm.menus.filter { $0.displayOrder >= 0 } }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    if vm.isLoading && vm.menus.isEmpty {
                        LoadingPlaceholderView()
                    } else if vm.menus.isEmpty {
                        EmptyStateView()
                    } else {
                        // Hardcoded restaurants
                        ForEach(hardcodedMenus) { menu in
                            RestaurantCardView(menu: menu)
                        }

                        // Separator + user restaurants
                        if !userMenus.isEmpty {
                            HStack {
                                VStack { Divider() }
                                Text("Custom")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize()
                                VStack { Divider() }
                            }
                            .padding(.horizontal, 4)

                            ForEach(userMenus) { menu in
                                RestaurantCardView(menu: menu)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            Divider()
            FooterView(openWindow: openWindow)
        }
        .frame(width: 340, height: 480)
        .background(.background)
        .task { await vm.onAppear() }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @EnvironmentObject private var vm: MenuViewModel

    var body: some View {
        HStack {
            Image(systemName: "fork.knife")
                .foregroundStyle(.secondary)
            Text("NivyBar")
                .font(.headline)
            Spacer()
            if vm.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            } else {
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Refresh menus")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Footer

private struct FooterView: View {
    @EnvironmentObject private var vm: MenuViewModel
    let openWindow: OpenWindowAction

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            Text("Aktualizované: \(vm.lastUpdatedLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Custom restaurant count hint
            if vm.userRestaurantCount > 0 {
                Text("\(vm.userRestaurantCount) custom")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Settings gear
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Restaurant settings")

            Button("Ukončiť") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Restaurant Card

struct RestaurantCardView: View {
    let menu: RestaurantMenu

    private var iconColor: Color {
        if let hex = menu.accentColorHex { return Color(hex: hex) }
        return Color.accentColor
    }

    private var icon: String {
        switch menu.restaurantName {
        case "Pivovar Komín": return "mug.fill"
        case "Nostalgia Nivy": return "fork.knife"
        default:              return "fork.knife.circle"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Accent color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(iconColor)
                .frame(width: 4)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 0) {
                // Card header
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(menu.restaurantName)
                            .font(.system(size: 12, weight: .semibold))
                        if let price = menu.unifiedPrice {
                            Text(price)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.12))
                                )
                        }
                    }
                    Text(menu.zone)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 6)

            // Card body
            if menu.hasError {
                ErrorRowView(message: menu.error ?? "Neznáma chyba.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let soup = menu.soup {
                        SoupRowView(item: soup)
                    }
                    ForEach(Array(menu.dishes.enumerated()), id: \.offset) { index, dish in
                        if index > 0 {
                            Divider()
                                .padding(.horizontal, 10)
                        }
                        DishRowView(item: dish)
                    }
                }
                .padding(.bottom, 6)
            }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        )
        .drawingGroup()
    }
}

// MARK: - Soup Row

private struct SoupRowView: View {
    let item: MenuItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("🍜")
                .font(.system(size: 11))
                .padding(.top, 1)
            Text(item.name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
    }
}

// MARK: - Dish Row

private struct DishRowView: View {
    let item: MenuItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.name)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            Spacer(minLength: 8)
            if let price = item.price {
                Text(price)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

// MARK: - Error Row

private struct ErrorRowView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .imageScale(.small)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

// MARK: - Loading placeholder

private struct LoadingPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text("Načítavam menu…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    @EnvironmentObject private var vm: MenuViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Žiadne menu")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Načítať menu") {
                Task { await vm.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Preview

#Preview {
    let vm = MenuViewModel()
    ContentView()
        .environmentObject(vm)
}
