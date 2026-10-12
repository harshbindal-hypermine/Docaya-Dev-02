# Docaya prototype release notes

## 8 September 2026 — Azure hosted demo, notification center and split audit trail

[Open the live application](https://sthmaihrnhp04.z13.web.core.windows.net/docayapro/) · [Publishing instructions](../README.md#publish-the-hosted-demo-azure-storage-static-website)

- **Hosted demo moved to Azure Storage.** The prototype is now published to the `$web/docayapro/` folder of storage account `sthmaihrnhp04` and served at [https://sthmaihrnhp04.z13.web.core.windows.net/docayapro/](https://sthmaihrnhp04.z13.web.core.windows.net/docayapro/). The build uses `/docayapro/` as its asset base. GitHub Pages is no longer used because the private repository's plan does not support it.
- **Notification center.** The bell opens a summary with metric cards (pending my approval, overdue approvals, expiring within 30 days, unread) and highlighted needs-attention rows; the badge shows a live count.
- **Audit trail split into two views.** The Audit page now provides a **Document audit trail** (filterable by document) and a **User audit trail** (filterable by user), each with its own CSV export.

## 6 September 2026 — selected branding and client demo

[Open the live application](https://sthmaihrnhp04.z13.web.core.windows.net/docayapro/) · [Run locally](../README.md#run-locally) · [Client demonstration guide](prototype-demo.md)

### Approved visual identity

- **Main Docaya identity:** the selected [three-dimensional emerald D folder artwork](../public/brand/docaya-welcome.png) appears in full on the login screen and as a compact, centred 60 px image in the top-left brand area. The favicon and Apple touch icon reference the same image.
- **Ask Docaya AI:** the selected [D speech-bubble logo with a white sparkle](../public/brand/ask-docaya-mark.png) identifies the floating assistant, its panel and responses, and search and discovery features.
- Native **Docaya / دوكايا** labels use bundled Inter and Noto Sans Arabic. The workspace retains readable document surfaces, muted gold accents and a subtle UAE-inspired background.
- The selected source images are unchanged. The earlier flat Docaya logo and `-v2` explorations remain available as reference assets.

[Login preview](images/docaya-login.png) · [Workspace and assistant preview](images/docaya-assistant.png) · [Brand guide and original prompts](branding.md)

### Current demonstration experience

| Area                     | Available behavior                                                                                                                                                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Approval queue           | Pending documents appear in **To review**, ordered by due date. Search and **Overdue only** narrow the queue; **Returned** separates documents awaiting changes.                                                   |
| Document review          | A drawer keeps the desktop queue, document preview and review details visible together. Approvers can approve and sign, or return a document with a required explanation. Navigation to the next item is explicit. |
| Document intake          | Upload an original or select a synthetic sample, inspect automatic classification suggestions, override metadata and confirm the classification before submission.                                                 |
| Search and Ask Docaya    | Switch between thumbnails and a list, filter indexed records, and open the documents cited by answers. The floating assistant uses the selected AI logo.                                                           |
| Arabic and accessibility | English/Arabic layouts, bundled fonts, keyboard controls and responsive document views support client demonstrations.                                                                                              |
| Governance and workshops | Demonstrate records retention, holds, correspondence, reporting, audit history and capture of client expectations.                                                                                                 |

See the [demonstration guide](prototype-demo.md) for the walkthrough and the implemented/future scope of M1–M15.

### Validation and publishing

The canonical repository is [hypermine2050/Docaya-Pro](https://github.com/hypermine2050/Docaya-Pro), and the prototype is published to an Azure Storage static website at [https://sthmaihrnhp04.z13.web.core.windows.net/docayapro/](https://sthmaihrnhp04.z13.web.core.windows.net/docayapro/) with `/docayapro/` as the asset base.

The selected-branding application revision [`2350baf`](https://github.com/hypermine2050/Docaya-Pro/commit/2350baf011cc767b09527ae43f71e977f3a3ad8e) passed production build, lint and formatting checks. Desktop and Arabic mobile visual checks found no broken images, page overflow or automated accessibility violations on the checked screens. GitHub's quality workflow, including the prototype browser journeys, and the Pages deployment both succeeded. The published login, main logo, AI logo and favicon were verified against the selected files.

The [publishing workflow](../.github/workflows/prototype-pages.yml) deploys after a successful push quality run on `main`. See [validation commands](../README.md#validate-changes) and [publishing instructions](../README.md#publish-to-github-pages) for subsequent updates.

### Prototype scope

This remains a UI/UX demonstration using synthetic records and simulated AI, identity and integrations. Documents and workshop notes persist in the current browser; GitHub synchronization does not copy browser workspace data. See [prototype boundaries](../README.md#data-and-prototype-boundaries) before preparing a client demonstration.
