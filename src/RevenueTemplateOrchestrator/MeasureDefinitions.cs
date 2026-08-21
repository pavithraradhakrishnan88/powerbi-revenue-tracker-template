namespace RevenueTemplateOrchestrator;

/// <summary>
/// Single source of truth for every DAX measure in the Revenue Tracker semantic model.
///
/// LESSON CARRIED OVER FROM powerbi-pipeline-sla-template:
/// The SLA project's original PatchMeasures method was additive-only — it could add a
/// brand-new measure to the TMDL, but if a measure with the same name already existed
/// with a *different* expression, the old (wrong) expression silently won because the
/// patcher never looked for an existing block to replace. That produced the
/// "SLAStatus = Breached" bug: the DAX kept comparing against a literal that didn't
/// exist in the data, and no amount of re-running the patcher fixed it, because the
/// patcher wasn't touching existing measures at all.
///
/// The fix, reused here: RevenueSemanticModelWriter always does a full reconcile pass —
/// for every measure in this catalog it finds-and-replaces the existing block by name,
/// or appends it if missing. There is no "assume it's new" code path.
///
/// Also deliberately avoided this time: IsRefund is stored as an int64 0/1 flag, not a
/// free-text status string, specifically so no DAX measure can silently diverge from the
/// column's actual values the way `SLAStatus = "Breached"` did against `"Missed"`.
/// </summary>
public static class MeasureDefinitions
{
    public static readonly List<MeasureDefinition> All = new()
    {
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Total Revenue",
            Expression: "SUM(Fact_Revenue[Revenue])",
            FormatString: "\\₹#,0;(\\₹#,0)",
            DisplayFolder: "Core"
        ),
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Total Orders",
            Expression: "CALCULATE(COUNTROWS(Fact_Revenue), Fact_Revenue[IsRefund] = 0)",
            FormatString: "#,0",
            DisplayFolder: "Core"
        ),
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Total Refunds",
            Expression: "CALCULATE(COUNTROWS(Fact_Revenue), Fact_Revenue[IsRefund] = 1)",
            FormatString: "#,0",
            DisplayFolder: "Core"
        ),
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Refund Rate %",
            Expression: "DIVIDE([Total Refunds], [Total Refunds] + [Total Orders], 0)",
            FormatString: "0.0%",
            DisplayFolder: "Core"
        ),
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Average Order Value",
            Expression: "DIVIDE([Total Revenue], [Total Orders], 0)",
            FormatString: "\\₹#,0.00",
            DisplayFolder: "Core"
        ),
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Revenue Previous Month",
            // MonthYear is stored as zero-padded "YYYY-MM" text specifically so lexical
            // string comparison (<, >) is equivalent to chronological comparison — avoids
            // needing a certified date table / DATEADD for a simple prior-month lookup.
            Expression =
                "VAR CurrentMonthYear = MAX(Dim_MonthYear[MonthYear])\n" +
                "VAR PreviousMonthYear =\n" +
                "    CALCULATE(\n" +
                "        MAX(Dim_MonthYear[MonthYear]),\n" +
                "        FILTER(ALL(Dim_MonthYear), Dim_MonthYear[MonthYear] < CurrentMonthYear)\n" +
                "    )\n" +
                "RETURN\n" +
                "    CALCULATE(\n" +
                "        [Total Revenue],\n" +
                "        ALL(Dim_MonthYear),\n" +
                "        Dim_MonthYear[MonthYear] = PreviousMonthYear\n" +
                "    )",
            FormatString: "\\₹#,0",
            DisplayFolder: "Growth"
        ),
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Revenue MoM Growth %",
            Expression =
                "VAR Prev = [Revenue Previous Month]\n" +
                "RETURN DIVIDE([Total Revenue] - Prev, Prev, BLANK())",
            FormatString: "0.0%;-0.0%",
            DisplayFolder: "Growth"
        ),
        new MeasureDefinition(
            Table: "Dim_Target",
            Name: "Target Revenue",
            Expression: "SUM(Dim_Target[TargetRevenue])",
            FormatString: "\\₹#,0",
            DisplayFolder: "Targets"
        ),
        new MeasureDefinition(
            Table: "Dim_Target",
            Name: "Target Achievement %",
            Expression: "DIVIDE([Total Revenue], [Target Revenue], 0)",
            FormatString: "0.0%",
            DisplayFolder: "Targets"
        ),
        new MeasureDefinition(
            Table: "Fact_Revenue",
            Name: "Revenue Share by Channel %",
            Expression: "DIVIDE([Total Revenue], CALCULATE([Total Revenue], ALL(Dim_Channel)), 0)",
            FormatString: "0.0%",
            DisplayFolder: "Channel"
        ),
    };
}

public record MeasureDefinition(
    string Table,
    string Name,
    string Expression,
    string FormatString,
    string DisplayFolder
);
