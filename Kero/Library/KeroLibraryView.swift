//
//  KeroLibraryView.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Every game: systems and collections on the left, a searchable, sortable cover grid (or list) on
//  the right. Choosing a game opens its details.
//

import SwiftUI

import KeroEngine

struct KeroLibraryView: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        GeometryReader { geometry in
            let railWidth: CGFloat = geometry.size.width < 900 ? 196 : 232

            HStack(spacing: 0) {
                KeroLibraryRail(model: self.model)
                    .frame(width: railWidth)

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)
                    .ignoresSafeArea()

                KeroLibraryMain(model: self.model)
            }
        }
        .background(KeroTheme.background.ignoresSafeArea())
    }
}

// MARK: - Rail -

private struct KeroLibraryRail: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        let rail = self.model.railItems

        VStack(alignment: .leading, spacing: 24) {
            KeroWordmark()
                .frame(height: 40)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        self.heading("SYSTEMS")
                        ForEach(Array(rail.enumerated()), id: \.offset) { index, item in
                            if case .filter(let filter) = item, self.isSystemFilter(filter)
                            {
                                self.row(item, index: index)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        self.heading("COLLECTIONS")
                        ForEach(Array(rail.enumerated()), id: \.offset) { index, item in
                            if case .filter(let filter) = item, !self.isSystemFilter(filter)
                            {
                                self.row(item, index: index)
                            }
                        }
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.hidden)
            .padding(-4)

            Spacer(minLength: 0)

            let addIndex = rail.firstIndex(of: .addGames) ?? rail.count - 1
            Button {
                KeroFeedback.select()
                self.model.select(.addGames)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add Games")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(KeroTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .keroFocusRing(self.isFocused(addIndex), shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(KeroPressStyle())
        }
        .padding(.top, 26)
        .padding(.leading, 28)
        .padding(.trailing, 18)
        .padding(.bottom, 24)
    }

    private func isSystemFilter(_ filter: KeroLibraryFilter) -> Bool
    {
        switch filter
        {
        case .all, .system: return true
        case .favorites, .recentlyAdded, .fanTranslations: return false
        }
    }

    private func isFocused(_ index: Int) -> Bool
    {
        return self.model.showsFocus && self.model.libraryFocus == .rail(index)
    }

    private func heading(_ text: String) -> some View
    {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(KeroTheme.tertiaryText)
            .padding(.bottom, 6)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func row(_ item: KeroRailItem, index: Int) -> some View
    {
        if case .filter(let filter) = item
        {
            let isSelected = self.model.libraryFilter == filter
            let isSystem = self.isSystemFilter(filter)

            Button {
                KeroFeedback.tap()
                self.model.select(item)
            } label: {
                HStack(spacing: 10) {
                    self.icon(for: filter, isSelected: isSelected)
                        .frame(width: 16)
                    Text(self.title(for: filter))
                        .font(.system(size: 14, weight: isSystem || isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if isSystem || isSelected
                    {
                        Text("\(self.model.count(for: filter))")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.7)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(isSelected ? KeroTheme.background : KeroTheme.mutedText)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(isSelected ? KeroTheme.primaryText : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .keroFocusRing(self.isFocused(index), shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(self.title(for: filter)), \(self.model.count(for: filter)) games"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func title(for filter: KeroLibraryFilter) -> String
    {
        return filter == .all ? "All" : filter.title
    }

    @ViewBuilder
    private func icon(for filter: KeroLibraryFilter, isSelected: Bool) -> some View
    {
        switch filter
        {
        case .all:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? KeroTheme.background : KeroTheme.mutedText)
                .frame(width: 10, height: 10)
        case .system(let system):
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(KeroTheme.dot(for: system))
                .frame(width: 10, height: 10)
        case .favorites:
            Image(systemName: "star.fill")
                .font(.system(size: 13))
                .foregroundStyle(KeroTheme.favorite)
        case .recentlyAdded:
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .semibold))
        case .fanTranslations:
            Text("汉")
                .font(.system(size: 12, weight: .heavy))
        }
    }
}

// MARK: - Main -

private struct KeroLibraryMain: View
{
    @ObservedObject var model: KeroHomeModel
    @FocusState private var isSearching: Bool

    var body: some View
    {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = geometry.size.width < 640 ? 20 : 36
            let available = geometry.size.width - horizontalPadding * 2
            let columns = min(6, max(2, Int((available + 18) / (128 + 18))))
            let games = self.model.libraryGames

            VStack(alignment: .leading, spacing: 20) {
                self.header(compact: geometry.size.width < 720)
                    .padding(.horizontal, horizontalPadding)

                if games.isEmpty
                {
                    self.emptyState
                        .padding(.horizontal, horizontalPadding)
                }
                else
                {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Group {
                                if self.model.libraryIsList
                                {
                                    LazyVStack(spacing: 6) {
                                        ForEach(Array(games.enumerated()), id: \.element.identifier) { index, game in
                                            KeroLibraryRow(model: self.model, game: game, isFocused: self.isFocused(index))
                                                .id(game.identifier)
                                        }
                                    }
                                }
                                else
                                {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 18), count: columns), spacing: 22) {
                                        ForEach(Array(games.enumerated()), id: \.element.identifier) { index, game in
                                            KeroLibraryCard(model: self.model, game: game, isFocused: self.isFocused(index))
                                                .id(game.identifier)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: self.model.libraryFocus) { _, focus in
                            guard case .grid(let index) = focus, games.indices.contains(index) else { return }
                            withAnimation(KeroTheme.focusSpring) { proxy.scrollTo(games[index].identifier, anchor: .center) }
                        }
                    }
                }
            }
            .padding(.top, 26)
            .onAppear { self.model.libraryColumns = columns }
            .onChange(of: columns) { _, columns in self.model.libraryColumns = columns }
            .onChange(of: self.isSearching) { _, isSearching in self.model.isTyping = isSearching }
        }
    }

    private func isFocused(_ index: Int) -> Bool
    {
        return self.model.showsFocus && self.model.libraryFocus == .grid(index)
    }

    private func header(compact: Bool) -> some View
    {
        let games = self.model.libraryGames

        return HStack(spacing: 14) {
            Button {
                self.model.showHome()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(KeroTheme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(KeroTheme.surfaceStrong, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(KeroPressStyle())
            .accessibilityLabel("Back to Home")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.model.libraryFilter.title)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(KeroTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(games.count)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KeroTheme.tertiaryText)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                TextField("Search", text: self.$model.librarySearch)
                    .font(.system(size: 14))
                    .foregroundStyle(KeroTheme.primaryText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused(self.$isSearching)
                    .accessibilityLabel("Search games")
                if !self.model.librarySearch.isEmpty
                {
                    Button {
                        self.model.librarySearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .foregroundStyle(KeroTheme.secondaryText)
            .padding(.horizontal, 14)
            .frame(width: compact ? 160 : 260, height: 40)
            .background(KeroTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(KeroTheme.stroke, lineWidth: 1))

            Menu {
                Picker("Sort", selection: self.$model.librarySort) {
                    ForEach(KeroLibrarySort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if !compact
                    {
                        Text(self.model.librarySort.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    else
                    {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(KeroTheme.mutedText)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(KeroTheme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(KeroTheme.stroke, lineWidth: 1))
                .contentShape(Capsule())
            }
            .accessibilityLabel(Text("Sort by \(self.model.librarySort.title)"))

            HStack(spacing: 0) {
                self.viewToggle(isList: false, symbol: "square.grid.2x2.fill", label: "Grid view")
                self.viewToggle(isList: true, symbol: "list.bullet", label: "List view")
            }
            .padding(3)
            .background(KeroTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(KeroTheme.stroke, lineWidth: 1))
        }
        .frame(height: 40)
    }

    private func viewToggle(isList: Bool, symbol: String, label: String) -> some View
    {
        let isSelected = self.model.libraryIsList == isList

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { self.model.libraryIsList = isList }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSelected ? KeroTheme.background : KeroTheme.mutedText)
                .frame(width: 34, height: 32)
                .background(isSelected ? KeroTheme.primaryText : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var emptyState: some View
    {
        VStack(alignment: .leading, spacing: 10) {
            if self.model.games.isEmpty
            {
                Text("No games yet")
                    .font(.system(size: 20, weight: .bold))
                Text("Add game files you own from Files, a folder, AirDrop or Wi-Fi Transfer.")
                    .font(.system(size: 14))
                    .foregroundStyle(KeroTheme.secondaryText)
                Button {
                    self.model.host?.showImport()
                } label: {
                    KeroPrimaryPill(title: "Add Games", symbol: "plus", height: 44, fontSize: 15, horizontalPadding: 22)
                }
                .buttonStyle(KeroPressStyle())
                .padding(.top, 6)
            }
            else if !self.model.librarySearch.isEmpty
            {
                Text("No matches for “\(self.model.librarySearch)”")
                    .font(.system(size: 20, weight: .bold))
                Text("Try another name, or search all games.")
                    .font(.system(size: 14))
                    .foregroundStyle(KeroTheme.secondaryText)
            }
            else
            {
                Text(self.emptyTitle)
                    .font(.system(size: 20, weight: .bold))
                Text(self.emptyText)
                    .font(.system(size: 14))
                    .foregroundStyle(KeroTheme.secondaryText)
            }
        }
        .foregroundStyle(KeroTheme.primaryText)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyTitle: String {
        switch self.model.libraryFilter
        {
        case .favorites: return "No favorites yet"
        case .fanTranslations: return "No fan translations"
        default: return "Nothing here"
        }
    }

    private var emptyText: String {
        switch self.model.libraryFilter
        {
        case .favorites: return "Tap the star on a game (or press X on a controller) to keep it here."
        case .fanTranslations: return "Chinese fan translations (汉化) Kero recognises show up here."
        default: return "No games in this list."
        }
    }
}

// MARK: - Cards -

private struct KeroLibraryCard: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    var isFocused: Bool

    var body: some View
    {
        Button {
            KeroFeedback.select()
            self.model.openDetails(self.game)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                KeroGameCover(game: self.game, cornerRadius: 16, showsTitle: false)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(KeroTheme.stroke, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if self.game.isFavorite
                        {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(KeroTheme.favorite)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                                .padding(.top, 9)
                                .padding(.trailing, 10)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if self.game.isChineseTranslation
                        {
                            KeroTranslationBadge()
                                .padding(10)
                        }
                    }
                    .keroFocusRing(self.isFocused, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(self.game.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KeroTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(KeroLibraryText.meta(self.game, isRunning: self.model.isRunning(self.game)))
                    .font(.system(size: 12))
                    .foregroundStyle(KeroTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeroPressStyle())
        .contextMenu { KeroGameMenuItems(model: self.model, game: self.game, includesDetails: true) }
        .accessibilityLabel(Text("\(self.game.name), \(self.game.system.name)\(self.game.isFavorite ? ", favorite" : "")"))
    }
}

private struct KeroLibraryRow: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    var isFocused: Bool

    var body: some View
    {
        Button {
            KeroFeedback.select()
            self.model.openDetails(self.game)
        } label: {
            HStack(spacing: 14) {
                KeroGameCover(game: self.game, cornerRadius: 12, showsTitle: false)
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KeroTheme.stroke, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.game.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KeroTheme.primaryText)
                        .lineLimit(1)
                    Text(self.game.system.name + " · " + KeroLibraryText.meta(self.game, isRunning: self.model.isRunning(self.game)))
                        .font(.system(size: 12))
                        .foregroundStyle(KeroTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if self.game.isChineseTranslation
                {
                    KeroTranslationBadge()
                }
                if self.game.isFavorite
                {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(KeroTheme.favorite)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KeroTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .background(self.isFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .keroFocusRing(self.isFocused, shape: RoundedRectangle(cornerRadius: 14, style: .continuous), gap: 2, width: 2)
        }
        .buttonStyle(KeroPressStyle())
        .contextMenu { KeroGameMenuItems(model: self.model, game: self.game, includesDetails: true) }
        .accessibilityLabel(Text("\(self.game.name), \(self.game.system.name)"))
    }
}

/// White "汉化" tag for Chinese fan translations.
struct KeroTranslationBadge: View
{
    var body: some View
    {
        Text("汉化")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KeroTheme.background)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(KeroTheme.primaryText, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Chinese fan translation")
    }
}

enum KeroLibraryText
{
    /// "Played 2 h ago", "Yesterday", "Never played".
    static func meta(_ game: KeroGame, isRunning: Bool) -> String
    {
        if isRunning { return "Paused" }
        guard let played = game.playedDate else { return "Never played" }

        let when = KeroFormat.when(played)
        return Calendar.current.isDateInToday(played) ? "Played " + when.lowercasedFirst : when
    }
}
