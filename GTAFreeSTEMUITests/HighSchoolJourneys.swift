import UIKit
import XCTest

/// Real installed app and reviewed bundle; run only on the disposable named QA simulator.
@MainActor
final class HighSchoolJourneys: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.rupayonhaldar.gtafreestem")
    override func setUpWithError() throws { continueAfterFailure = false }
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func reveal(_ item: XCUIElement, in application: XCUIApplication? = nil, swipeX: CGFloat = 0.5) {
        let surface = application ?? app
        for step in 0..<16 {
            let bounds = surface.frame
            let navigation = surface.navigationBars.firstMatch
            let top = navigation.exists ? max(bounds.minY + 40, navigation.frame.maxY) : bounds.minY + 80
            var bottom = bounds.maxY - 40
            let keyboard = surface.keyboards.firstMatch
            if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
            let identifier = item.exists ? item.identifier : ""
            let choicesOpen = surface.descendants(matching: .any).matching(identifier: "navigation-choices").firstMatch.exists
            let isFooter = identifier.hasPrefix("tab-") && !choicesOpen
            let isNavigationControl = !identifier.isEmpty && surface.navigationBars.descendants(matching: .any)
                .matching(identifier: identifier).firstMatch.exists
            if application == nil && !isFooter && !choicesOpen {
                let footer = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'")).firstMatch
                if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY) }
            }
            let frame = item.exists ? item.frame : .zero
            // XCTest previously called an offscreen guide button at y910..959 hittable,
            // then tapped y934 below the actual footer (y839..914), in the Home gesture area.
            // Require its centre in the observed content viewport before accepting a hit.
            if item.exists && item.isHittable && (isFooter || isNavigationControl || (frame.midY >= top && frame.midY < bottom)) { return }
            let swipeUp = frame.height > 0 ? frame.midY >= (top + bottom) / 2 : step < 8
            let height = max(80, bottom - top)
            let origin = surface.coordinate(withNormalizedOffset: .zero)
            let high = origin.withOffset(CGVector(dx: bounds.width * swipeX, dy: top - bounds.minY + height * 0.2))
            let low = origin.withOffset(CGVector(dx: bounds.width * swipeX, dy: top - bounds.minY + height * 0.8))
            if swipeUp { low.press(forDuration: 0.05, thenDragTo: high) }
            else { high.press(forDuration: 0.05, thenDragTo: low) }
        }
        let snapshot = XCTAttachment(screenshot: surface.screenshot()); snapshot.name = "unreachable-control"; snapshot.lifetime = .keepAlways; add(snapshot)
        let hierarchy = XCTAttachment(string: surface.debugDescription); hierarchy.name = "unreachable-control-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTFail("The requested control did not enter the observed content viewport after bounded scrolling.")
    }
    private func tap(_ id: String) {
        if id.hasPrefix("tab-") && id != "tab-navigation-menu" {
            let menu = element("tab-navigation-menu")
            if menu.exists && menu.isHittable { menu.tap() }
        }
        let item = element(id)
        reveal(item)
        XCTAssertTrue(item.waitForExistence(timeout: 5), id)
        XCTAssertTrue(item.isHittable, id); item.tap()
    }
    private func launchSchool() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()
        // The shell and its footer can appear after launch returns. Wait for an
        // actual navigation control before deciding which footer is active.
        let footerControl = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-")).firstMatch
        XCTAssertTrue(footerControl.waitForExistence(timeout: 15))
        reveal(footerControl)
        XCTAssertTrue(footerControl.isHittable)
        tap("tab-highSchool")
        // Lazy pathway cards enter the accessibility tree as the user scrolls,
        // especially at the largest system text size.
        let firstPathway = element("school-pathway-volunteer")
        reveal(firstPathway)
        XCTAssertTrue(firstPathway.waitForExistence(timeout: 15))
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways
        add(shot)
    }
    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func choose(_ id: String, _ value: String) {
        tap(id)
        let choice = app.buttons.matching(NSPredicate(format: "label == %@", value)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), value); choice.tap()
    }
    func test00ActivitiesTransitionIsUsable() {
        launchSchool(); tap("school-open-activities")
        capture("00-activities-transition")
        XCTAssertEqual(app.state, .runningForeground)
        reveal(element("browse-query"))
        XCTAssertTrue(element("browse-query").exists)
        let query = element("browse-query")
        query.tap(); query.typeText("QA keyboard transition")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(element("tab-highSchool").exists, "The main-page keyboard hides its footer")
        tap("browse-filters")
        let sheetQuery = element("filter-query")
        XCTAssertTrue(sheetQuery.waitForExistence(timeout: 5))
        sheetQuery.tap(); sheetQuery.typeText(" modal")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("00-main-keyboard-to-modal")
        tap("done-filters")
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed)
        XCTAssertTrue(element("tab-highSchool").waitForExistence(timeout: 5))
        XCTAssertTrue(element("tab-highSchool").isHittable, "The footer returns after the modal keyboard")
        capture("00-footer-restored")
        tap("school-return-hub")
        XCTAssertTrue(element("school-pathway-volunteer").waitForExistence(timeout: 5))
    }
    func test01GuideFiltersAndExistingSavedActivityNavigation() {
        let presetName = "QA school " + String(UUID().uuidString.prefix(8))
        launchSchool()
        XCTAssertFalse(element("school-untranslated-notice").exists)
        capture("01-real-guide-light")
        for key in ["volunteer", "learning", "leadership-careers", "funding"] {
            tap("school-pathway-" + key)
            XCTAssertTrue(app.staticTexts["Optional guide filters"].waitForExistence(timeout: 5))
            let firstRecord = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'school-record-'")).firstMatch
            reveal(firstRecord); XCTAssertTrue(firstRecord.exists)
            capture("02-pathway-" + key); back()
        }
        tap("school-pathway-volunteer")
        choose("school-filter-age", "18"); choose("school-filter-grade", "Grade 12")
        choose("school-filter-region", "York"); choose("school-filter-delivery", "Includes online activity")
        let yres = element("school-record-yres-volunteer-success-program")
        reveal(yres); XCTAssertTrue(yres.exists); capture("03-grade12-age18-york-online")
        yres.tap(); XCTAssertTrue(app.staticTexts["Commitment"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Commitment"])
        capture("04-real-yres-conditions"); back(); back()
        tap("school-open-activities")
        capture("04b-activities-after-transition")
        XCTAssertEqual(app.state, .runningForeground)
        reveal(element("browse-query"))
        XCTAssertTrue(element("browse-query").waitForExistence(timeout: 5))
        if element("browse-query-clear").exists { tap("browse-query-clear") }
        tap("browse-filters")
        let query = element("filter-query"); XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap(); query.typeText("QA pathway archive")
        // Actual failure evidence showed generic Done was done-filters, dismissing
        // the sheet. Save is an accessible navigation control above the keyboard.
        tap("save-named-search")
        let name = element("saved-search-name"); XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(presetName)
        tap("confirm-save-search")
        XCTAssertTrue(element("filter-save-confirmed").waitForExistence(timeout: 10))
        tap("done-filters"); tap("school-return-hub")
        tap("school-open-activities"); tap("browse-filters")
        tap("saved-filter-picker")
        let saved = app.buttons[presetName]; XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
        XCTAssertEqual(element("filter-query").value as? String, "QA pathway archive")
        capture("05-existing-preset-retained"); tap("done-filters"); tap("school-return-hub")
        XCTAssertTrue(element("school-pathway-volunteer").exists)
    }
    private func dismissHoursKeyboard() {
        XCTAssertTrue(["Record completed work", "Edit completed work", "Add hours", "Edit hours"].contains { app.navigationBars[$0].exists })
        if app.keyboards.firstMatch.exists {
            let done = app.buttons["hours-keyboard-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        }
        XCTAssertTrue(["Record completed work", "Edit completed work", "Add hours", "Edit hours"].contains { app.navigationBars[$0].exists })
    }
    private func openNotebook() {
        // Switching tabs preserves the School navigation stack. After Delete All
        // the notebook may already be open; inspect that real screen before tapping.
        let notebook = app.navigationBars["My completed hours"]
        if notebook.exists && notebook.isHittable { return }
        tap("school-hours-notebook")
    }
    private func fill(_ id: String, _ value: String) { tap(id); element(id).typeText(value) }
    func test02ActualNotebookEditRelaunchCsvCancelAndDeleteAll() {
        launchSchool()
        // The disposable QA app may retain the previous failed run's records.
        // Reset through the actual Delete All flow before asserting exact totals.
        tap("tab-account"); tap("account-delete-all-local"); tap("account-confirm-delete-all")
        XCTAssertTrue(element("account-operation-message").waitForExistence(timeout: 10))
        tap("tab-highSchool"); openNotebook(); tap("hours-add")
        fill("hours-provider", "QA Library"); fill("hours-role", "Completed sorting QA")
        fill("hours-minutes", "30"); fill("hours-notes", "Completed work recorded by QA")
        dismissHoursKeyboard()
        tap("hours-save")
        XCTAssertTrue(app.staticTexts["Completed sorting QA"].waitForExistence(timeout: 10))
        capture("06-notebook-committed")
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hours-edit-'")).firstMatch
        reveal(edit); edit.tap()
        let minutes = element("hours-minutes")
        reveal(minutes)
        XCTAssertEqual(minutes.value as? String, "30")
        // Use normal keyboard replacement rather than the system's optional
        // long-press edit menu, whose animation waits dominated the failed trace.
        minutes.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        // UI-focus flags aren't keyboard-first-responder proof on this iOS runtime.
        // Route real keyboard input through the application, without targeting a field.
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(minutes.value as? String, "3", "Keyboard input must reach the actual minutes field")
        app.typeText(XCUIKeyboardKey.delete.rawValue + "45")
        XCTAssertEqual(minutes.value as? String, "45")
        dismissHoursKeyboard()
        tap("hours-save")
        XCTAssertTrue(app.staticTexts["0 h 45 min self-recorded"].waitForExistence(timeout: 10))
        app.terminate(); launchSchool(); openNotebook()
        XCTAssertTrue(app.staticTexts["0 h 45 min self-recorded"].waitForExistence(timeout: 10))
        capture("07-notebook-relaunch")
        tap("hours-export-latest")
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "The actual system export picker must open")
        XCTAssertTrue(save.isEnabled)
        let filename = app.textFields["DOCPicker.filenameTextField"]
        capture("08-system-csv-chooser")
        if !filename.exists {
            // iOS 27 opens inside On My iPhone without exposing the filename.
            // Return through the observed native Browse back control first.
            let browse = app.navigationBars.buttons["Browse"].firstMatch
            if browse.exists && browse.isHittable { browse.tap() }
        }
        capture("08b-system-csv-root")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "08b-system-csv-root-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        // The suggested filename is a FileExporter construction contract. Assert
        // its native field only on system presentations that actually expose it.
        if filename.exists {
            XCTAssertEqual(filename.value as? String, "gta-hours-notebook")
        }
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            // Cancel the native sheet by pulling its header down, never Save.
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            top.press(forDuration: 0.1, thenDragTo: bottom)
        }
        let pickerGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [pickerGone], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["0 h 45 min self-recorded"].waitForExistence(timeout: 10))
        XCTAssertFalse(filename.exists)
        tap("tab-account"); tap("account-delete-all-local"); tap("account-confirm-delete-all")
        XCTAssertTrue(element("account-operation-message").waitForExistence(timeout: 10))
        tap("tab-highSchool"); openNotebook()
        XCTAssertTrue(app.staticTexts["0 h 0 min self-recorded"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Completed sorting QA"].exists)
        app.terminate(); launchSchool(); openNotebook()
        XCTAssertTrue(app.staticTexts["0 h 0 min self-recorded"].waitForExistence(timeout: 10))
        capture("09-delete-all-no-resurrection")
    }
    func test06SetRealSystemReduceMotion() {
        // Run before increasing text size; the Settings switch is the real OS setting.
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let accessibility = settings.cells.containing(.staticText, identifier: "Accessibility").firstMatch
        reveal(accessibility, in: settings); accessibility.tap()
        let motion = settings.buttons["MOTION_TITLE"]
        reveal(motion, in: settings)
        XCTAssertTrue(motion.isHittable); motion.tap()
        XCTAssertTrue(settings.navigationBars["Motion"].waitForExistence(timeout: 10))
        let reduced = settings.switches["Reduce Motion"]
        XCTAssertTrue(reduced.waitForExistence(timeout: 10))
        if reduced.value as? String != "1" {
            // The exposed switch spans its whole row; its centre is the label.
            // Tap the observed native toggle at the right edge of that row.
            reduced.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: reduced)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        XCTAssertEqual(reduced.value as? String, "1")
        let shot = XCTAttachment(screenshot: settings.screenshot())
        shot.name = "real-settings-reduce-motion"; shot.lifetime = .keepAlways; add(shot)
        settings.terminate()
    }
    func test03DarkLargestTextAndRealSystemReducedMotion() {
        // The previous Settings stage enables the real OS option; check that it persisted.
        XCTAssertTrue(UIAccessibility.isReduceMotionEnabled)
        launchSchool(); capture("10-dark-largest-text-reduced-motion-guide")
        let compactMenu = element("tab-navigation-menu")
        XCTAssertTrue(compactMenu.exists && compactMenu.isHittable)
        XCTAssertLessThanOrEqual(compactMenu.frame.height, app.frame.height * 0.20)
        tap("school-pathway-volunteer")
        choose("school-filter-age", "18"); choose("school-filter-grade", "Grade 12")
        let yres = element("school-record-yres-volunteer-success-program")
        reveal(yres); yres.tap(); capture("11-dark-largest-text-provider-conditions")
        back(); back(); openNotebook(); tap("hours-add")
        XCTAssertTrue(app.navigationBars["Add hours"].waitForExistence(timeout: 5))
        fill("hours-provider", "QA accessibility"); fill("hours-role", "Completed QA work")
        // Dismiss the real keyboard before scrolling to the next field when
        // accessibility text leaves only a short form viewport above it.
        dismissHoursKeyboard()
        fill("hours-minutes", "15")
        capture("12-dark-largest-text-keyboard")
        dismissHoursKeyboard()
        tap("hours-save")
        XCTAssertTrue(app.staticTexts["0 h 15 min self-recorded"].waitForExistence(timeout: 10))
        capture("13-dark-largest-text-notebook")
    }

    func test07LargestTextNavigationMenu() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()
        let menu = element("tab-navigation-menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); XCTAssertTrue(menu.isHittable)
        XCTAssertLessThanOrEqual(menu.frame.height, app.frame.height * 0.20)
        for (key, label) in [("home", "Home"), ("browse", "Browse"), ("highSchool", "High School"), ("support", "Support"), ("account", "Profile")] {
            let currentLabel = menu.label
            menu.tap()
            var selectedCount = 0
            for choice in ["home", "browse", "highSchool", "support", "account"] {
                let option = element("tab-" + choice)
                XCTAssertTrue(option.waitForExistence(timeout: 5), choice)
                if option.isSelected {
                    selectedCount += 1
                    XCTAssertEqual(option.label, currentLabel)
                }
            }
            XCTAssertEqual(selectedCount, 1, "Exactly the current destination is selected")
            capture("max-navigation-options-" + key)
            let done = element("navigation-done")
            XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
            XCTAssertEqual(menu.label, currentLabel, "Closing choices keeps the current destination")
            menu.tap()
            let choice = element("tab-" + key)
            reveal(choice)
            XCTAssertTrue(choice.isHittable); choice.tap()
            XCTAssertTrue(menu.waitForExistence(timeout: 5)); XCTAssertEqual(menu.label, label)
        }
    }

    func test08SaveActualCsvFromLatestNotebook() {
        // This is invoked only on a newly created disposable QA simulator.
        launchSchool(); openNotebook(); tap("hours-add")
        fill("hours-provider", "QA, Library"); fill("hours-role", "QA sorting")
        fill("hours-minutes", "30"); fill("hours-notes", "Checked, \"done\"")
        dismissHoursKeyboard(); tap("hours-save")
        XCTAssertTrue(app.staticTexts["QA sorting"].waitForExistence(timeout: 10))
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hours-edit-'")).firstMatch
        reveal(edit); edit.tap()
        let minutes = element("hours-minutes"); reveal(minutes)
        XCTAssertEqual(minutes.value as? String, "30")
        minutes.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(minutes.value as? String, "3")
        app.typeText(XCUIKeyboardKey.delete.rawValue + "45")
        XCTAssertEqual(minutes.value as? String, "45")
        dismissHoursKeyboard(); tap("hours-save")
        XCTAssertTrue(app.staticTexts["0 h 45 min self-recorded"].waitForExistence(timeout: 10))
        tap("hours-export-latest")
        let picker = app.otherElements["Browse View (Picker)"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let local = app.cells["DOC.sidebar.item.On My iPhone"]
        if local.exists && local.isHittable { local.tap() }
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled)
        capture("csv-actual-save-destination")
        save.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        let success = app.staticTexts["Exported the latest saved records. This is not school approval."]
        reveal(success)
        XCTAssertTrue(success.waitForExistence(timeout: 10))
        capture("csv-actual-save-completed")
    }

    func test09CancelCsvAfterActualSave() {
        // Runner compares the saved file and notebook bytes before and after this test.
        launchSchool(); openNotebook()
        XCTAssertTrue(app.staticTexts["0 h 45 min self-recorded"].waitForExistence(timeout: 10))
        tap("hours-export-latest")
        let picker = app.otherElements["Browse View (Picker)"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let browse = app.navigationBars.buttons["Browse"].firstMatch
        if browse.exists && browse.isHittable { browse.tap() }
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); XCTAssertTrue(cancel.isHittable)
        capture("csv-actual-cancel-root")
        cancel.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["0 h 45 min self-recorded"].waitForExistence(timeout: 10))
    }

    func test10BottomContentRemainsAboveNavigation() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_CA", "-navigation-diagnostic"]
        app.launch()
        let footer = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 15))

        func check(_ item: XCUIElement, _ name: String) {
            // Detail contains an interactive map. Start vertical scrolling in
            // the page gutter so the map does not consume the drag as a pan.
            reveal(item, swipeX: name == "detail" ? 0.02 : 0.5)
            XCTAssertTrue(item.exists, name)
            XCTAssertTrue(item.isHittable, name)
            XCTAssertLessThanOrEqual(item.frame.maxY, footer.frame.minY + 1, "\(name) is covered by navigation")
            capture("bottom-" + name)
        }

        check(element("home-content-end"), "home")
        let homeNote = app.staticTexts["For every age and interest. Check the provider’s page for eligibility and registration."]
        XCTAssertTrue(homeNote.exists && homeNote.isHittable)
        XCTAssertLessThanOrEqual(homeNote.frame.maxY, footer.frame.minY + 1)
        tap("tab-browse")
        let firstListing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Details: ")).firstMatch
        reveal(firstListing)
        XCTAssertTrue(firstListing.waitForExistence(timeout: 15))
        let visibleTitle = String(firstListing.label.dropFirst("Details: ".count)).components(separatedBy: ". Category: ").first ?? ""
        XCTAssertFalse(visibleTitle.isEmpty, "Use the title of a real visible result for the bounded search")
        firstListing.tap()
        check(app.buttons["Save"], "detail")
        back()
        reveal(app.buttons["Alerts"])
        XCTAssertTrue(app.buttons["Alerts"].isHittable, "Alerts should be reachable before the results")
        let query = element("browse-query")
        reveal(query)
        query.tap()
        query.typeText(visibleTitle + XCUIKeyboardKey.return.rawValue)
        let keyboardHidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 10), .completed)
        check(element("browse-last-result-source"), "browse")
        tap("browse-filters")
        let community = app.switches["Black-focused"]
        XCTAssertTrue(community.waitForExistence(timeout: 5))
        XCTAssertTrue(community.isHittable, "Community focus should be near the top of Filters")
        tap("done-filters")

        tap("tab-highSchool")
        check(element("school-open-activities"), "school")
        tap("school-hours-notebook")
        check(element("hours-export-latest"), "notebook")

        tap("tab-support")
        check(element("support-terms-link"), "support")
        tap("tab-account")
        check(element("account-support-link"), "account")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func test13SupportFilterUpdatesResultsSavesAndRestoresWithoutLeavingBrowse() {
        app.launchArguments = ["-frontend-layout-review", "-review-screen", "home",
                               "-review-language", "en", "-review-support", "-screenshot-mode"]
        app.launch()
        tap("tab-browse")
        tap("browse-filters")
        let sensory = app.switches["support-filter-sensory-friendly"]
        reveal(sensory); sensory.tap()
        let count = element("filter-result-count")
        reveal(count)
        XCTAssertTrue(app.staticTexts["1 result"].waitForExistence(timeout: 10))
        capture("support-filter-light")
        tap("save-named-search")
        let name = app.textFields["saved-search-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        let previous = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        name.typeText("Sample sensory filter")
        tap("confirm-save-search")
        XCTAssertTrue(element("filter-save-confirmed").waitForExistence(timeout: 10))
        tap("reset-filters")
        tap("saved-filter-picker")
        app.buttons["Sample sensory filter"].tap()
        reveal(sensory)
        XCTAssertEqual(sensory.value as? String, "1")
        reveal(count)
        XCTAssertTrue(app.staticTexts["1 result"].waitForExistence(timeout: 10))
        tap("done-filters")
        let listing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Details: Sample: Build a Solar Robot")).firstMatch
        reveal(listing); listing.tap()
        let provider = element("provider-support-details")
        reveal(provider)
        XCTAssertTrue(app.staticTexts["Sample: a quieter activity with a quiet break space."].exists)
        let checked = element("support-last-checked")
        reveal(checked)
        XCTAssertNil(checked.label.range(of: #"\d{4}-\d{2}-\d{2}T"#, options: .regularExpression), "Provider checks should use a readable date")
        capture("support-detail-light")
        app.terminate()
    }

    func test12AlertPreferencesOpenWithoutPermissionPromptInLightAndDarkRTL() {
        for (language, extra, name) in [
            ("en", [String](), "alerts-light"),
            ("ar", ["-review-dark", "-review-large-text"], "alerts-dark-large-rtl")
        ] {
            app.launchArguments = ["-frontend-layout-review", "-review-screen", "home-saved",
                                   "-review-language", language] + extra
            app.launch()
            tap("tab-browse")
            let alerts = element("browse-alerts")
            XCTAssertTrue(alerts.waitForExistence(timeout: 15))
            reveal(alerts)
            alerts.tap()
            let daily = app.switches["daily-reminder-toggle"]
            XCTAssertTrue(daily.waitForExistence(timeout: 10))
            XCTAssertTrue(daily.isHittable)
            XCTAssertEqual(daily.value as? String, "0", "Reminders must be opt-in")
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            XCTAssertFalse(springboard.alerts.firstMatch.exists, "Opening settings must not request notification permission")
            capture(name)
            let savedToggle = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved-filter-alert-")).firstMatch
            reveal(savedToggle)
            XCTAssertTrue(savedToggle.exists && savedToggle.isHittable)
            XCTAssertEqual(savedToggle.value as? String, "0", "Existing saved filters must stay opted out")
            app.terminate()
        }
    }

    func test11SampleAccessibilityNotesInLightAndDarkRTL() {
        let sample = "Sample: Step-free entrance; contact the provider for details."
        for (language, extra, heading, name) in [
            ("en", [String](), "Accessibility notes from the source", "notes-light"),
            ("ar", ["-review-dark", "-review-large-text"], "ملاحظات إمكانية الوصول من المصدر", "notes-dark-large-rtl")
        ] {
            app.launchArguments = ["-frontend-layout-review", "-review-screen", "calendar",
                                   "-review-language", language, "-review-accessibility-notes"] + extra
            app.launch()
            let note = app.staticTexts[sample]
            XCTAssertTrue(note.waitForExistence(timeout: 15), "The labelled app-owned sample must load")
            reveal(note)
            XCTAssertTrue(note.isHittable)
            capture(name + "-content")
            let header = app.staticTexts[heading]
            reveal(header)
            XCTAssertTrue(header.isHittable)
            capture(name + "-heading")
            app.terminate()
        }
    }

    func test05PhysicalPhoneReadOnlyJourney() {
        // Explicitly select only this test on an owner phone: no deletion, CSV write,
        // recorded-hours mutation, saved-filter write, fixture, or language override.
        app.launchArguments = []
        app.launch()
        let footerControl = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-")).firstMatch
        XCTAssertTrue(footerControl.waitForExistence(timeout: 15))
        reveal(footerControl); XCTAssertTrue(footerControl.isHittable)
        for tab in ["home", "browse", "highSchool"] {
            tap("tab-" + tab)
            capture("phone-" + tab)
        }
        let firstPathway = element("school-pathway-volunteer")
        reveal(firstPathway)
        XCTAssertTrue(firstPathway.waitForExistence(timeout: 10))
        for key in ["volunteer", "learning", "leadership-careers", "funding"] {
            tap("school-pathway-" + key)
            XCTAssertTrue(app.staticTexts["Optional guide filters"].waitForExistence(timeout: 5))
            capture("phone-pathway-" + key)
            back()
        }
        openNotebook()
        XCTAssertTrue(app.navigationBars["My completed hours"].waitForExistence(timeout: 10))
        capture("phone-notebook-read-only")
        tap("tab-account"); capture("phone-account-existing-settings")
        tap("tab-home")
        XCTAssertEqual(app.state, .runningForeground)
    }
    func test04NearLimitFictionalNotebookResponsiveness() {
        // Invoke separately only after the harness validates and stages the 2,000-entry fixture.
        launchSchool()
        for pass in 1...2 {
            let start = ProcessInfo.processInfo.systemUptime
            openNotebook()
            let total = app.staticTexts["33 h 20 min self-recorded"]
            XCTAssertTrue(total.waitForExistence(timeout: 15))
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let receipt = XCTAttachment(string: "Fictional 2000-entry archive; open \(pass); visible total after \(elapsed) seconds; includes UI automation overhead.")
            receipt.name = "near-limit-open-\(pass)"; receipt.lifetime = .keepAlways; add(receipt)
            XCTAssertLessThan(elapsed, 20)
            for _ in 0..<5 { app.swipeUp() }
            capture("14-near-limit-scroll-\(pass)")
            // Tab navigation preserves the notebook stack; return to the guide
            // explicitly before checking that the tab round-trip is responsive.
            back()
            tap("tab-account"); tap("tab-highSchool")
            XCTAssertTrue(element("school-pathway-volunteer").waitForExistence(timeout: 5))
        }
    }

}

// The separately staged near-limit fixture is never part of the app bundle or an owner data store.
