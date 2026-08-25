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
/// </summary>
public static class MeasureDefinitions
{
    public static readonly List<MeasureDefinition> All = new()
    {
        new MeasureDefinition("Fact_Revenue", "Total Revenue", "SUM(Fact_Revenue[Revenue])", "\\₹#,0;(\\₹#,0)", "Core"),
        new MeasureDefinition("Fact_Revenue", "Total Orders", "CALCULATE(COUNTROWS(Fact_Revenue), Fact_Revenue[IsRefund] = 0)", "#,0", "Core"),
        new MeasureDefinition("Fact_Revenue", "Total Refunds", "CALCULATE(COUNTROWS(Fact_Revenue), Fact_Revenue[IsRefund] = 1)", "#,0", "Core"),
        new MeasureDefinition("Fact_Revenue", "Refund Rate %", "DIVIDE([Total Refunds], [Total Refunds] + [Total Orders], 0)", "0.0%", "Core"),
        new MeasureDefinition("Fact_Revenue", "Average Order Value", "DIVIDE([Total Revenue], [Total Orders], 0)", "\\₹#,0.00", "Core"),
        new MeasureDefinition("Fact_Revenue", "Revenue Previous Month", "VAR CurrentMonthYear = MAX(Dim_MonthYear[MonthYear])\nVAR PreviousMonthYear = CALCULATE(MAX(Dim_MonthYear[MonthYear]), FILTER(ALL(Dim_MonthYear), Dim_MonthYear[MonthYear] < CurrentMonthYear))\nRETURN CALCULATE([Total Revenue], ALL(Dim_MonthYear), Dim_MonthYear[MonthYear] = PreviousMonthYear)", "\\₹#,0", "Growth"),
        new MeasureDefinition("Fact_Revenue", "Revenue MoM Growth %", "VAR Prev = [Revenue Previous Month]\nRETURN DIVIDE([Total Revenue] - Prev, Prev, BLANK())", "0.0%;-0.0%", "Growth"),
        new MeasureDefinition("Dim_Target", "Target Revenue", "SUM(Dim_Target[TargetRevenue])", "\\₹#,0", "Targets"),
        new MeasureDefinition("Dim_Target", "Target Achievement %", "DIVIDE([Total Revenue], [Target Revenue], 0)", "0.0%", "Targets"),
        new MeasureDefinition("Fact_Revenue", "Revenue Share by Channel %", "DIVIDE([Total Revenue], CALCULATE([Total Revenue], ALL(Dim_Channel)), 0)", "0.0%", "Channel"),

        // HTML Content custom-visual payloads. These intentionally return HTML/SVG only;
        // the report no longer depends on native chart serialization for the four overview visuals.
        new MeasureDefinition("Fact_Revenue", "RevenueKpiHtml", "VAR r = FORMAT([Total Revenue], \"₹#,0\") VAR g = FORMAT([Revenue MoM Growth %], \"0.0%\") VAR c = IF([Revenue MoM Growth %] >= 0, \"#0E9E82\", \"#C43C6E\") RETURN \"<div style='font-family:Segoe UI,sans-serif;background:#fff;border-radius:14px;padding:20px 22px;box-shadow:0 2px 12px rgba(216,210,240,.55);height:100%;color:#1F1B2E'><div style='font-size:12px;font-weight:600;margin-bottom:14px'>Total Revenue</div><div style='display:flex;justify-content:space-between;align-items:center'><div><div style='font-size:32px;font-weight:600'>\"&r&\"</div><div style='font-size:11px;color:#8B879C;margin-top:4px'>Selected scope</div><div style='display:inline-block;margin-top:10px;padding:3px 8px;border-radius:999px;background:#F3F0FF;color:\"&c&\";font-size:11px;font-weight:600'>\"&g&\" vs prior month</div></div><div style='width:76px;height:76px;border-radius:50%;background:conic-gradient(#7B5CFA 0 72%,#F1EEFB 72% 100%);display:flex;align-items:center;justify-content:center'><div style='width:58px;height:58px;border-radius:50%;background:#fff;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:600'>\"&FORMAT([Target Achievement %],\"0%\")&\"</div></div></div></div>\"", "", "HTML"),
        new MeasureDefinition("Fact_Revenue", "RevenueByProductHtml", "VAR m = MAXX(ALL(Dim_Product[ProductName]), [Total Revenue]) RETURN \"<div style='font-family:Segoe UI,sans-serif;background:#fff;border-radius:14px;padding:20px 22px;box-shadow:0 2px 12px rgba(216,210,240,.55);height:100%;color:#1F1B2E'><div style='font-size:12px;font-weight:600;margin-bottom:14px'>Total Revenue by ProductName</div>\" & CONCATENATEX(VALUES(Dim_Product[ProductName]), VAR n = Dim_Product[ProductName] VAR v = [Total Revenue] VAR w = FORMAT(DIVIDE(v,m,0)*100,\"0\") RETURN \"<div style='margin:9px 0'><div style='display:flex;justify-content:space-between;font-size:10.5px;color:#6F6A80'><span>\"&n&\"</span><b style='color:#1F1B2E'>\"&FORMAT(v,\"₹#,0\")&\"</b></div><div style='height:8px;background:#F1EEFB;border-radius:6px;margin-top:4px'><div style='height:8px;width:\"&w&\"%;background:#7B5CFA;border-radius:6px'></div></div></div>\", \"\", [Total Revenue], DESC) & \"</div>\"", "", "HTML"),
        new MeasureDefinition("Fact_Revenue", "RevenueTrendHtml", "VAR mx = MAXX(ALL(Dim_Date[MonthYear]), [Total Revenue]) VAR bars = CONCATENATEX(VALUES(Dim_Date[MonthYear]), VAR v=[Total Revenue] VAR h=FORMAT(DIVIDE(v,mx,0)*100,\"0\") VAR lab=Dim_Date[MonthYear] RETURN \"<div style='flex:1;text-align:center'><div style='height:150px;display:flex;align-items:flex-end;justify-content:center'><div style='width:18px;height:\"&h&\"%;background:#F0629B;border-radius:6px 6px 2px 2px'></div></div><div style='font-size:9px;color:#8B879C;margin-top:6px'>\"&RIGHT(lab,5)&\"</div></div>\", \"\", Dim_Date[MonthYear], ASC) RETURN \"<div style='font-family:Segoe UI,sans-serif;background:#fff;border-radius:14px;padding:20px 22px;box-shadow:0 2px 12px rgba(216,210,240,.55);height:100%;color:#1F1B2E'><div style='font-size:12px;font-weight:600;margin-bottom:8px'>Total Revenue by MonthYear</div><div style='display:flex;gap:8px;align-items:stretch;height:185px'>\"&bars&\"</div></div>\"", "", "HTML"),
        new MeasureDefinition("Fact_Revenue", "TargetVsActualHtml", "VAR mx = MAXX(ALL(Dim_Product[ProductName]), MAX([Total Revenue],[Target Revenue])) RETURN \"<div style='font-family:Segoe UI,sans-serif;background:#fff;border-radius:14px;padding:20px 22px;box-shadow:0 2px 12px rgba(216,210,240,.55);height:100%;color:#1F1B2E'><div style='font-size:12px;font-weight:600;margin-bottom:14px'>Total Revenue and Target Revenue by ProductName</div><div style='display:flex;gap:12px;height:210px;align-items:flex-end'>\" & CONCATENATEX(VALUES(Dim_Product[ProductName]), VAR n=Dim_Product[ProductName] VAR r=[Total Revenue] VAR t=[Target Revenue] RETURN \"<div style='flex:1;display:flex;flex-direction:column;align-items:center;gap:5px'><div style='width:100%;display:flex;gap:3px;align-items:flex-end;height:180px'><div title='Revenue' style='flex:1;height:\"&FORMAT(DIVIDE(r,mx,0)*100,\"0\")&\"%;background:#7B5CFA;border-radius:5px 5px 1px 1px'></div><div title='Target' style='flex:1;height:\"&FORMAT(DIVIDE(t,mx,0)*100,\"0\")&\"%;background:#F0629B;border-radius:5px 5px 1px 1px'></div></div><div style='font-size:8.5px;color:#8B879C;text-align:center'>\"&LEFT(n,18)&\"</div></div>\", \"\", [Total Revenue], DESC) & \"</div><div style='font-size:10px;color:#8B879C;margin-top:4px'>● Revenue &nbsp; ● Target</div></div>\"", "", "HTML"),
    };
}

public record MeasureDefinition(
    string Table,
    string Name,
    string Expression,
    string FormatString,
    string DisplayFolder
);