using System.Text;
using System.Text.Json;

namespace RevenueTemplateOrchestrator;

/// <summary>
/// Writes the root .pbip file. Without this, Power BI Desktop has nothing to double-click —
/// the SLA project originally generated the .Report and .SemanticModel folders correctly
/// but forgot the root .pbip pointer file, so nothing opened as a single project.
/// </summary>
public sealed class PbipProjectWriter
{
    private readonly string _outputRoot;
    private readonly string _projectName;

    public PbipProjectWriter(string outputRoot, string projectName)
    {
        _outputRoot = outputRoot;
        _projectName = projectName;
    }

    public void Write()
    {
        var pbip = new
        {
            version = "1.0",
            artifacts = new object[]
            {
                new { report = new { path = $"{_projectName}.Report" } }
            },
            settings = new { enableAutoRecovery = true }
        };

        var json = JsonSerializer.Serialize(pbip, new JsonSerializerOptions { WriteIndented = true });
        var path = Path.Combine(_outputRoot, $"{_projectName}.pbip");

        File.WriteAllText(path, json, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

        Console.WriteLine($"[PbipProjectWriter] Wrote {path}");
    }
}
