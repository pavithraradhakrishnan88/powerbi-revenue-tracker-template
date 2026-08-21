using System.Text;
using System.Text.RegularExpressions;

namespace RevenueTemplateOrchestrator;

/// <summary>
/// Patches DAX measures into the base TMDL table files and copies the semantic model
/// folder into the generated output.
///
/// Pitfalls carried over from powerbi-pipeline-sla-template (see the runbook) and
/// specifically guarded against here:
///
///  1. UTF-8 BOM corruption — Windows PowerShell 5.1's `Set-Content -Encoding utf8`
///     writes a BOM that TMDL's parser chokes on. We never touch PowerShell for file
///     writes; everything here goes through WriteAllTextNoBom.
///
///  2. "InvalidLineType: Unexpected line type: Empty" — caused by double blank lines
///     left behind after patching columns/measures. CollapseDoubleBlankLines() runs as
///     a final pass on every file this writer touches.
///
///  3. Column/measure ordering — TMDL wants columns declared before measures in a table
///     block. InsertMeasureBlock() always inserts measures after the last existing
///     `column` block and before the `partition` block, never at the top of the file.
///
///  4. Additive-only patching — every measure is matched by name via regex and replaced
///     in place if found; only genuinely new measures are appended. Nothing here assumes
///     "if it's not in my diff, it doesn't already exist."
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
        var block = RenderMeasureBlock(measure);

        // Match an existing "measure 'Name' = ..." block up to (but not including) the
        // next top-level "measure ", "column ", or "partition " keyword at the same
        // (single-tab) indent level, or end of file.
        var pattern = new Regex(
            $@"(?m)^\tmeasure '?{Regex.Escape(measure.Name)}'?\s*=.*?(?=^\t(measure|column|partition)\s|\z)",
            RegexOptions.Singleline);

        var match = pattern.Match(tmdlContent);
        if (match.Success)
        {
            return tmdlContent[..match.Index] + block + tmdlContent[(match.Index + match.Length)..];
        }

        // Not found — insert after the last column block, before the first partition block.
        var partitionMatch = Regex.Match(tmdlContent, @"(?m)^\tpartition\s");
        if (!partitionMatch.Success)
        {
            // No partition block (shouldn't happen for our tables) — append at end.
            return tmdlContent.TrimEnd('\n') + "\n\n" + block + "\n";
        }

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
