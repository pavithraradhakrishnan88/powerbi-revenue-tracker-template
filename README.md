# powerbi-revenue-tracker-template

A metadata-driven PBIP/PBIR Power BI template — same workflow as
`powerbi-pipeline-sla-template`, applied to a Revenue Tracker product for the Gumroad
template roadmap.

## Workflow (mirrors powerbi-pipeline-sla-template)

```
template/ (checked-in TMDL/PBIR skeleton, no measures baked in)
      │
      ▼
src/RevenueTemplateOrchestrator (.NET 8 console app)
      │  reads template/ + data/*.csv
      │  patches DAX measures into TMDL via reconciliation
      │  writes root .pbip
      ▼
generated/ (git-ignored — CI artifact, not committed)
      │
      ▼
scripts/Assert-*.ps1 (regression gates)
      │
      ▼
GitHub Actions: DesktopValidation-PBIP (Windows runner)
      │
      ▼
Artifacts: RevenueTracker.Report, RevenueTracker.SemanticModel, RevenueTracker.pbip
```

Same separation of concerns as the SLA tracker: `template/` holds the authoritative,
hand-authored TMDL/PBIR structure (tables, relationships, report pages, visuals — no
measures). The orchestrator's only job is to patch DAX measures in from a single
catalog (`MeasureDefinitions.cs`) and assemble the final PBIP output. Nothing rewrites
visual payloads, IDs, or weakens validation gates — same constraints Pavithra has
enforced on the SLA project.

## Data model (star schema)

- **Fact_Revenue** — one row per transaction (TransactionID, Date, ProductID, ChannelID,
  Quantity, UnitPrice, Revenue, IsRefund, Currency)
- **Dim_Date** — daily calendar, `MonthYear` stored as zero-padded `YYYY-MM` text so
  lexical comparison equals chronological comparison (avoids needing a certified date
  table for the MoM measures)
- **Dim_Product** — the five templates in the roadmap (Finance KPI, Pipeline SLA
  Tracker, PersonaNav Portal Lite, Weekly Ops Heatmap, HR Utilization)
- **Dim_Channel** — Gumroad / Etsy / Direct
- **Dim_Target** — monthly revenue target per product
- **Dim_MonthYear** — hidden bridge table with unique `MonthYear` values, so
  `Dim_Target` (monthly grain) can relate safely to `Dim_Date` (daily grain) without
  putting a non-unique column on the "one" side of a relationship

## Measures

Defined once in `src/RevenueTemplateOrchestrator/MeasureDefinitions.cs`:
Total Revenue, Total Orders, Total Refunds, Refund Rate %, Average Order Value,
Revenue Previous Month, Revenue MoM Growth %, Target Revenue, Target Achievement %,
Revenue Share by Channel %.

## Lessons carried over from powerbi-pipeline-sla-template (and how they're avoided here)

| SLA project bug | Root cause | Fix applied in this repo |
|---|---|---|
| `SLA Compliance %` always 100% | DAX compared against a string literal (`"Breached"`) that didn't exist in the data (`"Missed"`/`"Met"` were the real values) | `IsRefund` is an int64 0/1 flag, not a free-text status — no string literal to drift from the real values |
| Measures silently kept stale expressions | Patcher was additive-only: only handled brand-new measure names, never replaced existing ones | `RevenueSemanticModelWriter.ReconcileMeasure` always finds-and-replaces by name first, appends only if truly absent |
| `InvalidLineType: Unexpected line type: Empty` | Double blank lines left in TMDL after patching | `CollapseDoubleBlankLines()` runs on every file the writer touches, plus a CI gate re-checks it |
| UTF-8 BOM corruption in `visual.json` | Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a BOM | All file writes go through .NET `UTF8Encoding(false)`, never PowerShell `Set-Content` |
| `.platform` stripped from CI artifacts | `actions/upload-artifact@v4` defaults `include-hidden-files` to `false`, dropping dotfiles | `include-hidden-files: true` set explicitly on every upload step |
| Absolute CI runner paths baked into CSV partitions | Runner working directory ended up in the TMDL `File.Contents(...)` path | Partitions reference bare filenames (`Fact_Revenue_SampleData.csv`); CSVs are copied to sit alongside the semantic model at generation time |
| `$LASTEXITCODE` check fired unconditionally | A PowerShell statement between the `dotnet` call and the check reset `$LASTEXITCODE` | Every dotnet call is followed *immediately* by its own dedicated exit-code-check step, nothing in between |
| Missing `reportExtensions.json` → `NullReferenceException` on open | File never generated | Checked into `template/RevenueTracker.Report/definition/`, verified present by `Assert-PbirPageLayoutGate.ps1` |
| `totalPages: 0` on Desktop open | `pages.json` referenced a page name with no matching folder, or vice versa | `Assert-PbirPageLayoutGate.ps1` gates on the manifest/folder contract, plus unique z-index/tabOrder per visual |
| Missing root `.pbip` | Report + semantic model generated correctly but nothing tied them together | `PbipProjectWriter.cs` always writes `RevenueTracker.pbip` as the last step |

**Important, same as the SLA project:** a green CI run proves the generated artifacts
are *structurally* valid. It does not prove the `.pbip` renders cleanly in Power BI
Desktop — do a manual Desktop UAT pass before treating a release as shippable.

## Status tracking

Per standing instruction: **Notion is the single source of truth for status on this
project**, not GitHub. Track progress under the Pipeline SLA Tracker Template Catalog's
sibling entry for this template (or create a new "Revenue Tracker — Status Check" page
alongside it) rather than relying on GitHub issues/commits as the record.

## Running locally

```powershell
dotnet restore src/RevenueTemplateOrchestrator/RevenueTemplateOrchestrator.csproj
dotnet build src/RevenueTemplateOrchestrator/RevenueTemplateOrchestrator.csproj -c Release

dotnet run --project src/RevenueTemplateOrchestrator/RevenueTemplateOrchestrator.csproj `
  -c Release --no-build -- .\template .\data .\generated

.\scripts\Assert-MeasureExpressionParity.ps1 -GeneratedRoot .\generated
.\scripts\Assert-PbirPageLayoutGate.ps1 -GeneratedRoot .\generated
```

Then open `generated\RevenueTracker.pbip` in Power BI Desktop for UAT.

## What's stubbed vs. complete

- **Complete**: star schema TMDL, relationships, measure catalog + reconciliation
  patcher, root .pbip writer, one report page (Revenue Overview) with 4 visuals
  (Total Revenue card, Revenue by Product bar chart, Revenue Trend line chart,
  Target vs Actual column chart), CI workflow, both regression gate scripts, 561 rows
  of sample transaction data across 18 months.
- **Not built yet** (same next steps as the SLA project had at this stage): a
  drill-through / channel-detail page, slicers/bookmarks, a `.pbit` export step,
  and the `Prepare-DesktopArtifact.ps1`-equivalent packaging script for the final
  Gumroad zip. I haven't compiled the C# in this environment (no .NET SDK available
  here) — run `dotnet build` locally or let CI validate it before trusting it fully.
