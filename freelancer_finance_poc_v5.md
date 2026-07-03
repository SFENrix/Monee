# POC Implementation Guide: Freelancer Financial Tracker & AI Advisor

## Changelog

### v4 → v5
- **Tracker absorbs Manual Entry:** `QuickEntryFormView` + `QuickEntryViewModel` move from the standalone `Features/ManualEntry/` folder into `Features/Tracker/`. Tracker is now the umbrella for "view + add transactions" — dashboard summary, transaction list, and manual entry all in one feature group. Receipt Scanner (OCR) stays separate on purpose — different pipeline, different failure modes. Full tree: `File_Structure_v2.md`.
- Still-open item carried over from v4, unresolved: fate of `IncomeEstimateSheet` (§3.C).

### v3 → v4
- **Added App Navigation Shell** (§3.A, new): `RootTabView` now owns the single `TabView` for the app — Tracker / Profile / AI Buddy. Replaces the `TabView` that used to live directly in `ContentView.swift`.
- **Dashboard → Tracker:** same feature, same logic, relocated from `App/ContentView.swift` into `Features/Tracker/`, consistent with how every other feature (ReceiptScanner, ManualEntry, AIBuddy) is organized. Not a rewrite — a rename + relocation.
- **Profile promoted from modal to tab** (§3.D, new): the one-time `IncomeEstimateSheet` that fired once from `AIChatView` is superseded by a persistent Profile tab. Same underlying data (`UserFinancialProfile.estimatedMonthlyIncome`), different presentation — a page the user can return to anytime instead of a skippable sheet they see once.
- **Timeline reality check** (§4): original scope below was written against a 1-week timeline. Actual working timeline is **2 days**. Day-by-day breakdown hasn't been re-cut yet — treat §4 as historical scope reference, not the live schedule.
- **Open item:** what happens to the original onboarding nudge now that Profile is a tab instead of a blocking sheet? See §3.C note.

---

## 1. Concept Overview
**Target Audience:** Self-employed individuals / Freelancers in Indonesia.
**Core Value:** Provide clarity over financial conditions and reduce spending guilt through frictionless tracking (OCR) and an AI-driven contextual advisor.
**Secondary Feature:** On-demand Threshold-Based Savings (The Jar System) — generated only when explicitly prompted, and only built at all once the main features are working and explicitly greenlit. Until then it stays reference-only.
**Timeline:** Originally scoped as 1 Week (POC). Actual sprint is **2 days** — see §4.

## 2. Technical Stack
* **UI / Frontend:** **SwiftUI**.
* **Local Database:** **SwiftData**.
* **Text Extraction (OCR):** **Vision Framework (`VNRecognizeTextRequest`)**.
* **System Integration:** **Share Extensions, App Intents, and WidgetKit**.
* **AI Backend Adapter:** Protocol-driven adapter (Apple Intelligence and Siri for POC).

## 3. Core Architecture & Data Flow
Since the app is closely related to money and financial, it is made clear here that the app will be using IDR or Rupiah as the main and currently accepted currency, expect no scalability.

### A. App Navigation Shell
Single `TabView`, owned by `RootTabView` (`App/RootTabView.swift`), three tabs:

| Tab | Backing View(s) | Feature Folder |
|---|---|---|
| Tracker | `TrackerView` (list/summary) + `QuickEntryFormView` (manual add, presented as a sheet) | `Features/Tracker/` |
| Profile | `ProfileView` | `Features/Profile/` |
| AI Buddy | `AIChatView` | `Features/AIBuddy/` |

- **Tracker scope:** umbrella feature for transaction visibility *and* entry — dashboard summary, transaction list, and the manual-entry form all live under `Features/Tracker/`. Manual Entry is no longer a separate top-level feature folder. Receipt Scanner (OCR) stays its own folder — different pipeline, different failure modes, worth keeping isolated.
- **Deep-link routing:** Widget quick-entry and Share Extension receipt handoff both set `AppContainer.pendingRoute`. `RootTabView` switches the selected tab to Tracker the moment a route arrives — so whatever sheet Tracker is about to present is actually visible to the user, regardless of which tab they were on when the deep link fired.
- **UI status:** tab icons/labels are placeholder. UI team owns final iconography and interaction style — including whether AI Buddy keeps a `.search`-role tab or a standard one.

### B. The Input Pipeline (Data Sanitization & Extensibility)
We employ a strict "Local Parsing First" rule. The architecture is designed to accept modular input sources in the future.
1. **Entry Points:** Share Extension (from banking receipts) or Home Screen Widget (Deep Link) — surfaces inside the **Tracker** tab or Action Button that is configured with Apple Shortcuts to run the OCR feature (Text Recognition) to "read" and extract what transaction information is currently on the user's screen. The extracted information will then be shown as a rich notification that is editable, it functions as a confirmation window before passing the confirmed data to the in-app tracker on the background without having the user to open the app to manually input the transaction to the tracker.
2. **Extraction (Current Core):** Vision Framework natively extracts text blocks.
3. **Parsing:** Local Regex rules scan the text for `Total Amount`, `Date`, and predefined keywords.
4. **Storage:** Structured, sanitized data saves to `SwiftData`.
5. **Confirmation:** App triggers a Rich Local Notification to confirm or edit the parsed data.
6. **Future Scalability:** The pipeline's abstraction allows dropping in voice-to-text or bank API modules later without breaking the core flow.

### C. The AI Financial Buddy (Context-Aware Advisor)
1. **Trigger:** User opens the AI Buddy tab.
2. **Context Gathering:** App queries `SwiftData` for recent transaction history.
3. **Prompt Injection:** Formats local database records into a lightweight JSON system prompt.
4. **Execution:** Sends the secure prompt to the AI provider to get personalized spending advice based on confirmed local data.
5. **Chat History:** each chat session (prompts and responses) saves to the local database after every turn. User can revisit and continue past chats.
6. **Income baseline dependency:** when real income history is thin, the AI falls back to `UserFinancialProfile.estimatedMonthlyIncome` — now sourced from the **Profile** tab (§3.D) instead of a one-time setup sheet.

> **Open item:** the original `IncomeEstimateSheet` (blocking modal, fired once on first AI Buddy visit) is superseded by the Profile tab. Still undecided: fully remove the nudge and rely on the Profile tab being discoverable on its own, or replace the blocking sheet with a lighter one-time nudge (banner/badge) that points the user at the Profile tab instead. Needs a call before the next code batch touches this.

### D. Profile (NEW)
- **Purpose:** view/edit the financial baseline the AI Buddy and `CashReserveCalculator` fall back on when real transaction history is too sparse to trust.
- **Supersedes:** `IncomeEstimateSheet`. Same underlying data (`UserFinancialProfile.estimatedMonthlyIncome`), different presentation — a persistent page instead of a skippable one-time sheet.
- **POC scope:** intentionally minimal — a single editable field (estimated monthly income). Not expanding scope (business name, currency, category defaults, etc.) unless explicitly asked; documenting here so it doesn't quietly grow.
- **UI status:** placeholder `Form` styling — UI team owns final layout.

### E. Secondary Feature: Threshold Savings (On-Demand)
* **Status:** ON HOLD. Do not implement until all main features (Tracker, Input Pipeline, AI Buddy, Profile) are working end-to-end and this is explicitly greenlit.
* **Logic:** Calculates milestones only when triggered by a specific user prompt or setting toggle.
* **UI:** The Jar visualizations are strictly hidden by default and rendered dynamically only when the user requests a visualization of their savings goals.

## 4. Development Timeline
**⚠️ Reality check:** this breakdown was written for the original 1-week scope. Actual sprint is 2 days. Kept below as historical reference for feature ordering/dependencies — not a live schedule. Say the word if you want this re-cut into an actual 2-day plan.

* **Day 1:** Project setup, core SwiftData schema (Transactions), and base UI navigation.
* **Day 2:** Vision OCR implementation and Local Regex parsing pipeline.
* **Day 3:** System integrations (Share Extension setup, Widget Deep Links).
* **Day 4:** Rich Notifications for OCR confirmation and Manual Entry fallback UI.
* **Day 5:** AI Backend Adapter, SwiftData context gathering, and Chat UI implementation.
* **Day 6:** AI Prompt tuning, edge-case handling, and ensuring input pipeline modularity.
* **Day 7:** End-to-end testing, bug fixing, and TestFlight deployment.
