using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace ScriptAssyst.Desktop;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

internal sealed class MainForm : Form
{
    private readonly WebView2 view = new() { Dock = DockStyle.Fill };
    private readonly string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));

    private static readonly HashSet<string> AllowedOperations = new(StringComparer.Ordinal)
    {
        "status", "dashboard", "users", "groups", "ous", "gpos", "tasks"
    };

    public MainForm()
    {
        Text = "ScriptAssyst v1.0";
        Width = 1280;
        Height = 820;
        MinimumSize = new Size(900, 620);
        Controls.Add(view);
        Load += async (_, _) => await InitializeViewAsync();
    }

    private async Task InitializeViewAsync()
    {
        await view.EnsureCoreWebView2Async();
        view.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
        var page = Path.Combine(root, "UI", "index.html");
        if (!File.Exists(page))
        {
            MessageBox.Show($"Interfaccia non trovata: {page}", "ScriptAssyst");
            Close();
            return;
        }
        view.Source = new Uri(page);
    }

    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var message = JsonDocument.Parse(e.WebMessageAsJson);
            if (!message.RootElement.TryGetProperty("operation", out var operationElement))
                throw new InvalidOperationException("Richiesta priva dell'operazione.");
            var operation = operationElement.GetString();
            if (operation is null || !AllowedOperations.Contains(operation))
                throw new InvalidOperationException("Operazione non consentita.");

            var query = "";
            if (message.RootElement.TryGetProperty("query", out var queryElement))
            {
                if (queryElement.ValueKind != JsonValueKind.String)
                    throw new InvalidOperationException("Il parametro query deve essere testuale.");
                query = queryElement.GetString() ?? "";
                if (query.Length > 128)
                    throw new InvalidOperationException("Il parametro query supera 128 caratteri.");
            }

            var script = Path.Combine(root, "Backend", "Start-ScriptAssyst.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Backend PowerShell non trovato.", script);

            var psi = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-NonInteractive");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("RemoteSigned");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(script);
            psi.ArgumentList.Add("-Operation");
            psi.ArgumentList.Add(operation);
            psi.ArgumentList.Add("-Query");
            psi.ArgumentList.Add(query);

            using var process = Process.Start(psi) ?? throw new InvalidOperationException("Impossibile avviare PowerShell.");
            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            var output = await outputTask;
            var error = await errorTask;
            if (process.ExitCode != 0)
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "Backend PowerShell terminato con errore." : error.Trim());
            view.CoreWebView2.PostWebMessageAsJson(string.IsNullOrWhiteSpace(output)
                ? JsonSerializer.Serialize(new { success = false, operation, data = (object?)null, error = "Il backend non ha restituito dati." })
                : output.Trim());
        }
        catch (Exception ex)
        {
            view.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { success = false, error = ex.Message }));
        }
    }
}