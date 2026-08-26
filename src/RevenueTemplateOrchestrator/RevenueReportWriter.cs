namespace RevenueTemplateOrchestrator;

/// <summary>
/// Copies the report project and sample data into the generated output.
///
/// Pitfall carried over from powerbi-pipeline-sla-template: CI runners on GitHub Actions
/// previously baked the *absolute* Windows runner path into the CSV partition sources
/// (e.g. D:\a\repo\repo\data\Fact_...csv), which worked in CI but broke the moment a
/// customer opened the .pbip on their own machine. The fix — and the rule enforced here —
/// is that CSV source paths in the TMDL partitions must always stay relative
/// ("Fact_Revenue_SampleData.csv", no folder prefix), and the actual CSV files must sit
/// directly alongside the semantic model's data files so Power BI Desktop's relative-path
/// resolution finds them without any absolute path ever being written.
/// </summary>
public sealed class RevenueReportWriter
{
    private readonly string _templateRoot;
    private readonly string _dataRoot;
    private readonly string _outputRoot;

    public RevenueReportWriter(string templateRoot, string dataRoot, string outputRoot)
    {
        _templateRoot = templateRoot;
        _dataRoot = dataRoot;
        _outputRoot = outputRoot;
    }

    public void Write()
    {
        var sourceReportDir = Path.Combine(_templateRoot, "RevenueTracker.Report");
        var targetReportDir = Path.Combine(_outputRoot, "RevenueTracker.Report");
        CopyDirectory(sourceReportDir, targetReportDir);

        // The lavender theme is a required generated artifact, not merely a template-side
        // file. Materialize it explicitly and fail the GENERATE stage if the authoritative
        // template does not contain it. This prevents a later THEME gate from discovering
        // that generation silently dropped the design contract.
        var themeRelativePath = Path.Combine("StaticResources", "RegisteredResources", "RevenueTracker_LavenderTheme.json");
        var sourceThemePath = Path.Combine(sourceReportDir, themeRelativePath);
        var targetThemePath = Path.Combine(targetReportDir, themeRelativePath);
        if (!File.Exists(sourceThemePath))
        {
            throw new FileNotFoundException($"Authoritative Revenue Tracker theme is missing from the template: {sourceThemePath}");
        }
        if (!File.Exists(targetThemePath))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(targetThemePath)!);
            File.Copy(sourceThemePath, targetThemePath, overwrite: true);
        }

        // CSV files live next to the semantic model definition, matching the relative
        // "Fact_Revenue_SampleData.csv" style path baked into the TMDL partitions.
        var targetDataDir = Path.Combine(_outputRoot, "RevenueTracker.SemanticModel");
        Directory.CreateDirectory(targetDataDir);

        foreach (var csvFile in Directory.GetFiles(_dataRoot, "*.csv"))
        {
            var destFile = Path.Combine(targetDataDir, Path.GetFileName(csvFile));
            File.Copy(csvFile, destFile, overwrite: true);
        }

        Console.WriteLine("[RevenueReportWriter] Report project + sample CSVs copied with relative paths intact.");
        Console.WriteLine($"[RevenueReportWriter] Theme materialized: {targetThemePath}");
    }

    private static void CopyDirectory(string sourceDir, string targetDir)
    {
        Directory.CreateDirectory(targetDir);

        foreach (var file in Directory.GetFiles(sourceDir))
        {
            var destFile = Path.Combine(targetDir, Path.GetFileName(file));
            File.Copy(file, destFile, overwrite: true);
        }

        foreach (var dir in Directory.GetDirectories(sourceDir))
        {
            var destDir = Path.Combine(targetDir, Path.GetFileName(dir));
            CopyDirectory(dir, destDir);
        }
    }
}
