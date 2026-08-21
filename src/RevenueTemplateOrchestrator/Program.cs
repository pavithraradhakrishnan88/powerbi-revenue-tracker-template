namespace RevenueTemplateOrchestrator;

/// <summary>
/// Entry point. Usage:
///   dotnet run --project src/RevenueTemplateOrchestrator -- <templateRoot> <dataRoot> <outputRoot>
///
/// Note for the CI workflow (see .github/workflows/build-and-validate.yml): this process
/// returns a real non-zero exit code on failure via the try/catch below, specifically so
/// PowerShell's $LASTEXITCODE reflects a genuine failure. In the SLA project, a helper
/// script called dotnet inside a PowerShell function and then checked $LASTEXITCODE
/// immediately after — but $LASTEXITCODE reflects the *last native command*, and any
/// PowerShell statement in between (even a harmless one) resets it, so the check fired
/// unconditionally. The CI workflow here checks $LASTEXITCODE on the line directly after
/// the dotnet call, with nothing else in between.
/// </summary>
public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length != 3)
        {
            Console.Error.WriteLine("Usage: RevenueTemplateOrchestrator <templateRoot> <dataRoot> <outputRoot>");
            return 1;
        }

        var templateRoot = args[0];
        var dataRoot = args[1];
        var outputRoot = args[2];
        const string projectName = "RevenueTracker";

        try
        {
            Directory.CreateDirectory(outputRoot);

            new RevenueSemanticModelWriter(templateRoot, outputRoot).Write();
            new RevenueReportWriter(templateRoot, dataRoot, outputRoot).Write();
            new PbipProjectWriter(outputRoot, projectName).Write();

            Console.WriteLine($"[Program] Revenue Tracker artifacts generated at: {outputRoot}");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[Program] FAILED: {ex.GetType().Name}: {ex.Message}");
            Console.Error.WriteLine(ex.StackTrace);
            return 1;
        }
    }
}
