using System.Text;
using System.Text.RegularExpressions;

namespace RevenueTemplateOrchestrator;

/// <summary>
/// Patches DAX measures into the base TMDL table files and copies the semantic model
/// folder into the generated output.
/// </summary>
public sealed class RevenueSemanticModelWriter
{
    private readonly string _templateRoot;
    private readonly string _outputRoot;

    public RevenueSemanticModelWriter(string templateRoot, string outputRoot)
    {
        _templateRoot = templateRoot;
        _outputRoot = outputRoot;
    }

    public void Write()
    {
        var sourceModelDir = Path.Combine(_templateRoot, "RevenueTracker.SemanticModel");
        var targetModelDir = Path.Combine(_outputRoot, "RevenueTracker.SemanticModel");

        CopyDirectory(sourceModelDir, targetModelDir);

        var measuresByTable = MeasureDefinitions.All
            .Select(HtmlMeasureFormatMetadata.Resolve)
            .GroupBy(m => m.Table)
            .ToDictionary(g => g.Key, g => g.ToList());

        foreach (var (tableName, measures) in measuresByTable)
        {
            var tablePath = Path.Combine(targetModelDir, "definition", "tables", $"{tableName}.tmdl");
            if (!File.Exists(tablePath))
            {
                throw new InvalidOperationException(
                    $"MeasureDefinitions references table '{tableName}' but " +
                    $"{tablePath} does not exist. Add the base table TMDL first — " +
                    "measures are never used to create tables, only to patch them.");
            }

            var content = File.ReadAllText(tablePath);
            foreach (var measure in measures)
            {
                content = ReconcileMeasure(content, measure);
            }

            content = CollapseDoubleBlankLines(content);
            WriteAllTextNoBom(tablePath, content);
        }

        Console.WriteLine($"[RevenueSemanticModelWriter] Patched {measuresByTable.Sum(kv => kv.Value.Count)} " +
                           $"measures across {measuresByTable.Count} table(s).");
    }

    private static string ReconcileMeasure(string tmdlContent, MeasureDefinition measure)
    {
        if (string.IsNullOrWhiteSpace(measure.Expression))
            throw new InvalidOperationException($"Measure '{measure.Name}' has an empty expression.");

        if (string.IsNullOrWhiteSpace(measure.FormatString))
            throw new InvalidOperationException($"Measure '{measure.Name}' has an empty FormatString; refusing to emit invalid TMDL.");

        var block = RenderMeasureBlock(measure);
        var pattern = new Regex(
            $@"(?m)^\tmeasure '?{Regex.Escape(measure.Name)}'?\s*=.*?(?=^\t(measure|column|partition)\s|\z)",
            RegexOptions.Singleline);

        var match = pattern.Match(tmdlContent);
        if (match.Success)
        {
            return tmdlContent[..match.Index] + block + tmdlContent[(match.Index + match.Length)..];
        }

        var partitionMatch = Regex.Match(tmdlContent, @"(?m)^\tpartition\s");
        if (!partitionMatch.Success)
            return tmdlContent.TrimEnd('\n') + "\n\n" + block + "\n";

        return tmdlContent[..partitionMatch.Index] + block + "\n" + tmdlContent[partitionMatch.Index..];
    }

    private static string RenderMeasureBlock(MeasureDefinition measure)
    {
        var sb = new StringBuilder();
        var isMultiLine = measure.Expression.Contains('\n');

        sb.Append('\t').Append("measure '").Append(measure.Name).Append("' = ");

        if (isMultiLine)
        {
            sb.Append("\n\t\t\t");
            sb.Append(measure.Expression.Replace("\n", "\n\t\t\t"));
        }
        else
        {
            sb.Append(measure.Expression);
        }

        sb.Append('\n');
        sb.Append('\t').Append("\tformatString: ").Append(measure.FormatString).Append('\n');
        if (!string.IsNullOrWhiteSpace(measure.DisplayFolder))
            sb.Append('\t').Append("\tdisplayFolder: ").Append(measure.DisplayFolder).Append('\n');
        sb.Append('\t').Append("\tlineageTag = ").Append(SlugTag(measure.Name)).Append('\n');
        sb.Append('\n');
        sb.Append('\t').Append("\tannotation PBI_FormatHint = {\"isGeneralNumber\":true}\n");
        sb.Append('\n');

        return sb.ToString();
    }

    private static string SlugTag(string measureName) =>
        "measure-" + Regex.Replace(measureName.ToLowerInvariant(), @"[^a-z0-9]+", "-").Trim('-');

    private static string CollapseDoubleBlankLines(string content) =>
        Regex.Replace(content, @"(\r?\n){3,}", "\n\n");

    private static void WriteAllTextNoBom(string path, string content)
    {
        var encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
        File.WriteAllText(path, content, encoding);
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
