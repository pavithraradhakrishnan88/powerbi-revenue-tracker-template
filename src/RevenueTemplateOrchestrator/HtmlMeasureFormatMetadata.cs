namespace RevenueTemplateOrchestrator;

/// <summary>
/// Explicit format metadata for measures whose DAX returns HTML text.
///
/// HTML is the rendered value, but Power BI still requires a non-empty TMDL
/// formatString for every measure. Keep these values in the measure metadata
/// layer rather than allowing the TMDL writer to invent or omit them.
/// </summary>
public static class HtmlMeasureFormatMetadata
{
    private static readonly IReadOnlyDictionary<string, string> Formats =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["RevenueKpiHtml"] = "0",
            ["RevenueByProductHtml"] = "0",
            ["RevenueTrendHtml"] = "0.0%",
            ["TargetVsActualHtml"] = "0.0%",
            ["NavigationHtmlButtons"] = "0",
            ["RevenuePageHtml"] = "0",
            ["TargetPageHtml"] = "0.0%",
            ["DetailsPageHtml"] = "0",
        };

    public static MeasureDefinition Resolve(MeasureDefinition measure)
    {
        if (!string.IsNullOrWhiteSpace(measure.FormatString))
            return measure;

        if (Formats.TryGetValue(measure.Name, out var formatString))
            return measure with { FormatString = formatString };

        return measure;
    }

    public static bool TryGet(string measureName, out string formatString) =>
        Formats.TryGetValue(measureName, out formatString!);
}
