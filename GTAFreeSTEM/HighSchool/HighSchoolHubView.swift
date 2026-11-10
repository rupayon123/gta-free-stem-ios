import SwiftUI

private enum SchoolHubDestination: Hashable {
    case pathway(String), listing(String), notebook
}

struct HighSchoolHubView: View {
    @EnvironmentObject private var session: SessionStore
    @ObservedObject var youth: HighSchoolHubStore
    let openActivities: () -> Void
    @State private var selectedAge = ""
    @State private var selectedGrade = ""
    @State private var selectedRegion = ""
    @State private var selectedDelivery = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(session.text("hsGuide"))
                        .font(PortfolioTypography.caption).foregroundStyle(Brand.mutedText(for: scheme))
                    Text(session.text("hsFindNextStep")).font(PortfolioTypography.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(session.text("hsExploreIntro"))
                        .font(PortfolioTypography.body)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach([YouthHub.Pathway.volunteer, .learning, .leadershipCareers, .funding], id: \.rawValue) { pathway in
                            NavigationLink(value: SchoolHubDestination.pathway(pathway.rawValue)) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(pathway.artwork).resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                                    Text(pathway.title(session)).font(PortfolioTypography.headline).fixedSize(horizontal: false, vertical: true)
                                    Text(pathway.summary(session)).font(PortfolioTypography.subheadline).fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                                .cardSurface(cornerRadius: 18)
                            }
                            .buttonStyle(SpringPressButtonStyle())
                            .accessibilityIdentifier("school-pathway-\(pathway.rawValue)")
                        }
                    }
                    NavigationLink(value: SchoolHubDestination.notebook) {
                        Label(session.text("hsMyCompletedHours"), systemImage: "book.closed")
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }.buttonStyle(StoryButtonStyle(kind: .secondary)).accessibilityIdentifier("school-hours-notebook")
                    Text(session.text("hsNotebookCreditNotice"))
                        .font(PortfolioTypography.footnote).foregroundStyle(Brand.mutedText(for: scheme))
                    Button(session.text("hsBrowseActivities"), action: openActivities)
                        .buttonStyle(StoryButtonStyle(kind: .quiet))
                        .accessibilityIdentifier("school-open-activities")
                    if let error = youth.catalogueError {
                        Text(SchoolLocalized.message(error, session)).foregroundStyle(Brand.coral)
                        Button(session.text("hsRetryGuide")) { Task { await youth.loadCatalogue() } }
                            .buttonStyle(StoryButtonStyle(kind: .secondary))
                    }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(StorybookBackground())
            .navigationTitle(session.text("highSchool"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SchoolHubDestination.self) { destination in
                switch destination {
                case .pathway(let key):
                    if let pathway = YouthHub.Pathway(rawValue: key) { pathwayPage(pathway) }
                case .listing(let id):
                    if let listing = youth.listings.first(where: { $0.id == id }) {
                        YouthListingDetail(listing: listing, evaluation: evaluation(listing))
                    } else { Text(session.text("hsRecordNotInGuide")) }
                case .notebook: HoursNotebookView(youth: youth)
                }
            }
            .task { await youth.loadCatalogue() }
            .task(id: youth.listings.count) {
                guard AppLaunchConfiguration.isScreenshotCapture, !youth.listings.isEmpty else { return }
                await Task.yield()
                AppLaunchConfiguration.markScreenshotReady(youth.catalogueError == nil)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { youth.objectWillChange.send() }
            }
        }
        .environment(\.locale, Locale(identifier: session.language.localeIdentifier))
        .environment(\.layoutDirection, session.language.layoutDirection)
        .accessibilityIdentifier("school-hub")
    }

    private func pathwayPage(_ pathway: YouthHub.Pathway) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(pathway.summary(session)).font(PortfolioTypography.body)
                filterControls
                if pathway == .funding {
                    Text(session.text("hsOfficialFundingDisclaimer")).font(PortfolioTypography.callout)
                }
                if pathway == .volunteer {
                    let count = rows(pathway, kind: .role).filter { evaluation($0)?.verifiedFreeRoles == true }.count
                    Text(count == 0 ? session.text("hsNoVerifiedFreeRoles") : session.text("hsCheckEachRole"))
                        .font(PortfolioTypography.callout).accessibilityIdentifier("school-role-coverage")
                }
                listingSection(session.text("hsReviewedFreeProgramIntakes"), rows: rows(pathway, kind: .program).filter { evaluation($0)?.verifiedFreePrograms == true })
                listingSection(session.text("hsAskOrUpcomingPrograms"), rows: rows(pathway, kind: .program).filter { evaluation($0)?.verifiedFreePrograms != true })
                listingSection(session.text("hsIndividualRoles"), rows: rows(pathway, kind: .role))
                listingSection(session.text("hsPlacesToLook"), rows: rows(pathway, kind: .providerDirectory))
                listingSection(session.text("hsGuidanceResources"), rows: rows(pathway, kind: .resource))
                if !youth.listings.isEmpty && !youth.listings.contains(where: { $0.pathway == pathway && matches($0) }) {
                    Text(session.text("hsNoMatches"))
                }
                if youth.listings.isEmpty {
                    Text(youth.catalogueError.map { SchoolLocalized.message($0, session) } ?? session.text("hsReadingGuide"))
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(StorybookBackground()).navigationTitle(pathway.title(session))
    }
    private func evaluation(_ listing: YouthHub.Listing) -> YouthHub.Evaluation? {
        youth.evaluation(listing, age: Double(selectedAge), grade: Int(selectedGrade))
    }
    private func matches(_ listing: YouthHub.Listing) -> Bool {
        HighSchoolGuideSelection(age: Double(selectedAge), grade: Int(selectedGrade), region: selectedRegion,
                                 delivery: selectedDelivery).matches(listing, now: youth.timestamp)
    }
    private func costDescription(_ listing: YouthHub.Listing) -> String {
        switch evaluation(listing)?.costLabel {
        case "No fee evidenced": session.text("hsProviderListsFree")
        case "Required cost": session.text("hsRequiredCost")
        default: session.text("hsCheckCosts")
        }
    }
    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.text("hsOptionalFilters")).font(PortfolioTypography.headline)
            Text(session.text("hsFilterExplanation"))
                .font(PortfolioTypography.footnote)
            Picker(session.text("age"), selection: $selectedAge) {
                Text(session.text("hsAnyAge")).tag("")
                ForEach(12...25, id: \.self) { Text(SchoolLocalized.number($0, session)).tag(String($0)) }
            }.accessibilityIdentifier("school-filter-age")
            Picker(session.text("hsGrade"), selection: $selectedGrade) {
                Text(session.text("hsAnyGrade")).tag("")
                ForEach(7...12, id: \.self) { Text(SchoolLocalized.format(session, "hsGradeFormat", ["grade": SchoolLocalized.number($0, session)])).tag(String($0)) }
            }.accessibilityIdentifier("school-filter-grade")
            Picker(session.text("region"), selection: $selectedRegion) {
                Text(session.text("hsAnyRegion")).tag("")
                ForEach(Array(Set(youth.listings.flatMap { $0.regions ?? [] })).sorted(), id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("school-filter-region")
            Picker(session.text("hsDelivery"), selection: $selectedDelivery) {
                Text(session.text("hsAnyDelivery")).tag("")
                ForEach([YouthHub.Delivery.inPerson, .virtual, .hybrid], id: \.rawValue) { Text($0 == .virtual ? session.text("hsIncludesOnline") : $0 == .inPerson ? session.text("hsIncludesInPerson") : session.text("hsMixedDelivery")).tag($0.rawValue) }
            }.accessibilityIdentifier("school-filter-delivery")
            Button(session.text("hsClearFilters")) { selectedAge = ""; selectedGrade = ""; selectedRegion = ""; selectedDelivery = "" }
                .buttonStyle(StoryButtonStyle(kind: .quiet))
        }.pickerStyle(.menu).cardSurface()
    }
    private func rows(_ pathway: YouthHub.Pathway, kind: YouthHub.ListingKind) -> [YouthHub.Listing] {
        youth.listings.filter { $0.pathway == pathway && $0.listingKind == kind && matches($0) }
    }
    @ViewBuilder private func listingSection(_ title: String, rows: [YouthHub.Listing]) -> some View {
        if !rows.isEmpty {
            Text(title).font(PortfolioTypography.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.id) { row in
                NavigationLink(value: SchoolHubDestination.listing(row.id)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.translatedText(for: YouthTranslation.input(row, "title", row.title)))
                            .font(PortfolioTypography.headline)
                            .environment(\.layoutDirection, session.language.layoutDirection)
                        if session.language != .en, let notice = YouthTranslation.notice(session.translationState(for: YouthTranslation.input(row, "title", row.title)), session: session) {
                            Text(notice).font(PortfolioTypography.footnote)
                        }
                        Text(row.provider).font(PortfolioTypography.subheadline)
                        Text(row.listingKind == .providerDirectory ? session.text("hsDirectoryIndividualRoles") : SchoolLocalized.status(evaluation(row), listing: row, session: session))
                            .font(PortfolioTypography.caption)
                        if row.listingKind == .program || row.listingKind == .role {
                            Text(costDescription(row)).font(PortfolioTypography.caption)
                        }
                        if let delivery = row.delivery, delivery != .unknown {
                            Text(delivery == .hybrid ? session.text("hsMixedDelivery") : delivery == .virtual ? session.text("hsIncludesOnline") : session.text("hsIncludesInPerson"))
                                .font(PortfolioTypography.caption)
                        }
                        if row.regions == nil || row.delivery == nil || row.delivery == .unknown {
                            Text(session.text("hsLocationUnspecified")).font(PortfolioTypography.caption)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).cardSurface()
                }.buttonStyle(SpringPressButtonStyle())
                    .modifier(YouthTitleTranslationDemand(listing: row))
                    .accessibilityIdentifier("school-record-\(row.id)")
            }
        }
    }
}

private struct YouthListingDetail: View {
    @EnvironmentObject private var session: SessionStore
    let listing: YouthHub.Listing
    let evaluation: YouthHub.Evaluation?
    @Environment(\.colorScheme) private var scheme
    @State private var translationOwner = UUID()
    @State private var showOriginal = false
    private var inputs: [ListingTranslationInput] { YouthTranslation.detailInputs(listing) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                translated("title", listing.title).font(PortfolioTypography.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                    .environment(\.layoutDirection, session.language.layoutDirection)
                Text(listing.provider).font(PortfolioTypography.headline)
                Text(session.text("hsReviewedSummary"))
                    .font(PortfolioTypography.caption).foregroundStyle(Brand.mutedText(for: scheme))
                translationControls
                detail(session.text("hsWhoFor"), "audience", listing.audience.original)
                if let residency = listing.audience.residency { detail(session.text("hsResidency"), "residency", residency) }
                ForEach(Array((listing.audience.restrictions ?? []).enumerated()), id: \.offset) { index, value in
                    translated("restriction-\(index)", value).font(PortfolioTypography.body)
                        .environment(\.layoutDirection, session.language.layoutDirection)
                }
                if listing.listingKind == .program || listing.listingKind == .role {
                    detail(session.text("hsCostsExpenses"), "cost", listing.cost.original)
                    ForEach(Array(listing.cost.requiredCosts.enumerated()), id: \.offset) { index, value in
                        translated("required-cost-\(index)", value.description).font(PortfolioTypography.body)
                            .environment(\.layoutDirection, session.language.layoutDirection)
                    }
                    Text(SchoolLocalized.status(evaluation, listing: listing, session: session)).font(PortfolioTypography.body)
                    detail(session.text("hsAvailability"), "availability", listing.availability.original)
                } else {
                    Text(listing.pathway == .funding ? session.text("hsFundingNotPromised") : session.text("hsDirectoryIndividualChecks")).font(PortfolioTypography.callout)
                }
                if let commitment = listing.commitmentOriginal { detail(session.text("commitment"), "commitment", commitment) }
                if let hours = listing.hours.original {
                    detail(session.text("hsSchoolHours"), "hours", hours)
                } else if listing.listingKind == .program || listing.listingKind == .role {
                    detail(session.text("hsSchoolHours"), "hours-fallback", session.text("hsNoHoursPromise"))
                }
                Text(SchoolLocalized.format(session, "hsSourceCheckedFormat", ["date": SchoolLocalized.timestamp(listing.checkedAt, session)])).font(PortfolioTypography.caption)
                if evaluation?.evidenceCurrent != true {
                    Text(session.text("hsReviewNotCurrent"))
                        .foregroundStyle(Brand.coral)
                }
                if YouthHub.safeSourceURL(listing.sourceUrl), let url = URL(string: listing.sourceUrl) {
                    Link(destination: url) {
                        Text(listing.listingKind == .providerDirectory ? session.text("hsOpenDirectory") :
                             listing.listingKind == .program && evaluation?.applyNow == true ? session.text("hsViewProgramIntake") : session.text("hsCheckProviderSource"))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(StoryButtonStyle(kind: .primary))
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(StorybookBackground()).navigationTitle(session.text("hsReviewedDetails")).navigationBarTitleDisplayMode(.inline)
        .onAppear { session.setTranslationDemand(owner: translationOwner, inputs: inputs, priority: 100) }
        .onDisappear { session.removeTranslationDemand(owner: translationOwner) }
        .onChange(of: session.preferredLanguageCode) { _, _ in
            showOriginal = false
            session.setTranslationDemand(owner: translationOwner, inputs: inputs, priority: 100)
        }
        .onChange(of: inputs) { _, updated in session.setTranslationDemand(owner: translationOwner, inputs: updated, priority: 100) }
    }
    private func translated(_ field: String, _ value: String) -> Text {
        Text(showOriginal ? value : session.translatedText(for: YouthTranslation.input(listing, field, value)))
    }
    private func detail(_ title: String, _ field: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(PortfolioTypography.headline).accessibilityAddTraits(.isHeader)
            translated(field, value).font(PortfolioTypography.body).fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, session.language.layoutDirection)
        }
    }
    @ViewBuilder private var translationControls: some View {
        if session.language != .en {
            let states = inputs.map { session.translationState(for: $0) }
            if let state = states.first(where: { $0 == .failed || $0 == .unavailable }) ?? states.first(where: { $0 == .waiting }),
               let notice = YouthTranslation.notice(state, session: session) {
                Text(notice).font(PortfolioTypography.footnote)
                if state == .failed || state == .unavailable {
                    Button(session.text("translateListing")) { session.retryTranslations() }
                }
            }
            if states.contains(.translated) {
                Button(showOriginal ? session.text("translateListing") : session.text("showOriginal")) { showOriginal.toggle() }
                    .accessibilityIdentifier("school-listing-original")
            }
        }
    }
}

/// Only bundled public guide records enter this path; private notebook entries never do.
enum YouthTranslation {
    static func input(_ listing: YouthHub.Listing, _ field: String, _ source: String) -> ListingTranslationInput {
        .init(listingID: "youth:" + listing.id, field: field, source: source, sourceHint: listing.audience.original)
    }
    static func detailInputs(_ listing: YouthHub.Listing) -> [ListingTranslationInput] {
        var result = [input(listing, "title", listing.title), input(listing, "audience", listing.audience.original)]
        if let value = listing.audience.residency { result.append(input(listing, "residency", value)) }
        result += (listing.audience.restrictions ?? []).enumerated().map { input(listing, "restriction-\($0.offset)", $0.element) }
        if listing.listingKind == .program || listing.listingKind == .role {
            result.append(input(listing, "cost", listing.cost.original))
            result += listing.cost.requiredCosts.enumerated().map { input(listing, "required-cost-\($0.offset)", $0.element.description) }
            result.append(input(listing, "availability", listing.availability.original))
        }
        if let value = listing.commitmentOriginal { result.append(input(listing, "commitment", value)) }
        if let value = listing.hours.original { result.append(input(listing, "hours", value)) }
        return result
    }
    @MainActor static func notice(_ state: ListingTranslationState, session: SessionStore) -> String? {
        switch state {
        case .waiting: return session.text("translatingListing")
        case .unavailable: return session.text("translationUnavailable")
        case .failed: return session.text("translationFailed")
        case .original, .translated: return nil
        }
    }
}

private struct YouthTitleTranslationDemand: ViewModifier {
    @EnvironmentObject private var session: SessionStore
    @State private var owner = UUID()
    let listing: YouthHub.Listing
    private var input: ListingTranslationInput { YouthTranslation.input(listing, "title", listing.title) }
    func body(content: Content) -> some View {
        content
            .onAppear { session.setTranslationDemand(owner: owner, inputs: [input]) }
            .onDisappear { session.removeTranslationDemand(owner: owner) }
            .onChange(of: session.preferredLanguageCode) { _, _ in session.setTranslationDemand(owner: owner, inputs: [input]) }
            .onChange(of: input) { _, updated in session.setTranslationDemand(owner: owner, inputs: [updated]) }
    }
}

private extension YouthHub.Pathway {
    @MainActor func title(_ session: SessionStore) -> String {
        switch self {
        case .volunteer: session.text("hsVolunteer")
        case .learning: session.text("hsLearnCreate")
        case .leadershipCareers: session.text("hsLeadershipCareers")
        case .funding: session.text("hsScholarshipsSupport")
        }
    }
    @MainActor func summary(_ session: SessionStore) -> String {
        switch self {
        case .volunteer: session.text("hsVolunteerSummary")
        case .learning: session.text("hsLearningSummary")
        case .leadershipCareers: session.text("hsLeadershipSummary")
        case .funding: session.text("hsFundingSummary")
        }
    }
    var artwork: String {
        switch self {
        case .volunteer: "gta_volunteer_illustration"
        case .learning: "gta_ideas_illustration"
        case .leadershipCareers: "gta_school_illustration"
        case .funding: "gta_support_illustration"
        }
    }
}

/// Localizes presentation only; source records, notebook text and CSV remain untouched.
@MainActor
enum SchoolLocalized {
    static func format(_ session: SessionStore, _ key: String, _ values: [String: String]) -> String {
        var value = session.text(key)
        for (name, content) in values {
            let isolated = session.language.layoutDirection == .rightToLeft ? "\u{2068}" + content + "\u{2069}" : content
            value = value.replacingOccurrences(of: "{" + name + "}", with: isolated)
        }
        return value
    }
    static func number(_ value: Int, _ session: SessionStore) -> String {
        value.formatted(.number.grouping(.never).locale(Locale(identifier: session.language.localeIdentifier)))
    }
    static func enteredMinutes(_ text: String) -> Int? {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else { return nil }
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == text.count else { return nil }
        return Int(digits.map(String.init).joined())
    }
    private static func displayDate(_ date: Date, _ session: SessionStore, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: session.language.localeIdentifier)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }
    static func localDate(_ source: String, _ session: SessionStore) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: source) else { return source }
        return displayDate(date, session, timeZone: .current)
    }
    static func timestamp(_ source: String, _ session: SessionStore) -> String {
        guard let date = YouthHub.timestamp(source) else { return source }
        return displayDate(date, session, timeZone: TimeZone(identifier: "America/Toronto") ?? .current)
    }
    static func status(_ evaluation: YouthHub.Evaluation?, listing: YouthHub.Listing, session: SessionStore) -> String {
        guard let status = evaluation?.effectiveStatus else { return session.text("hsConfirmProvider") }
        switch status {
        case .open: return session.text("hsOpen")
        case .closed: return session.text("hsClosed")
        case .upcoming:
            guard let opens = listing.availability.opensAt, YouthHub.timestamp(opens) != nil else { return session.text("hsConfirmProvider") }
            return format(session, "hsOpensFormat", ["date": timestamp(opens, session)])
        case .unknown, .conflicting: return session.text("hsConfirmProvider")
        }
    }
    static func message(_ message: String, _ session: SessionStore) -> String {
        switch message {
        case "The reviewed guide could not be read. Try again; no replacement listings have been created.": return session.text("hsGuideReadFailed")
        case "Local deletion could not be confirmed. Retry Delete all local data.": return session.text("hsLocalDeleteUnconfirmed")
        case "This record changed elsewhere. Your draft is still here. Reload the latest record before choosing what to keep.": return session.text("hsConflictError")
        case "Check the date, actual minutes and text. A day cannot contain more than 1,440 recorded minutes.": return session.text("hsInvalidEntry")
        case "The saved notebook has an unsupported or damaged format. Its original file has been preserved.": return session.text("hsInvalidArchive")
        case "The notebook could not be read. Your saved file has not been replaced.": return session.text("hsReadFailed")
        case "The save could not be confirmed. Keep your draft and reload the latest notebook before retrying.": return session.text("hsWriteFailed")
        case "This record is no longer in the saved notebook. Your draft has been kept.": return session.text("hsEntryNotFound")
        default: return message
        }
    }
}
