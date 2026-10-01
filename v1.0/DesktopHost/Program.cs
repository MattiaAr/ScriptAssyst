using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace ScriptAssyst.Desktop;

internal static class Program
{
    [STAThread] private static void Main() { ApplicationConfiguration.Initialize(); Application.Run(new MainForm()); }
}

internal sealed class MainForm : Form
{
    private readonly WebView2 view = new() { Dock = DockStyle.Fill };
    private readonly string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
    public MainForm() { Text = "ScriptAssyst v1.0"; Width = 1280; Height = 820; MinimumSize = new Size(900, 620); Controls.Add(view); Load += async (_, _) => await InitializeViewAsync(); }
    private async Task InitializeViewAsync()
    {
        await view.EnsureCoreWebView2Async();
        view.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
        var page = Path.Combine(root, "UI", "index.html");
        if (!File.Exists(page)) { MessageBox.Show($"Interfaccia non trovata: {page}", "ScriptAssyst"); Close(); return; }
        view.Source = new Uri(page);
    }
    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var message = JsonDocument.Parse(e.WebMessageAsJson);
            var operation = message.RootElement.GetProperty("operation").GetString();
            if (operation is not ("status" or "dashboard")) throw new InvalidOperationException("Operazione non consentita.");
            var module = Path.Combine(root, "Backend", "ScriptAssyst.psm1").Replace("'", "''");
            var psi = new ProcessStartInfo("powershell.exe") { UseShellExecute=false, RedirectStandardOutput=true, RedirectStandardError=true, CreateNoWindow=true };
            psi.ArgumentList.Add("-NoProfile"); psi.ArgumentList.Add("-NonInteractive"); psi.ArgumentList.Add("-ExecutionPolicy"); psi.ArgumentList.Add("RemoteSigned"); psi.ArgumentList.Add("-Command");
            psi.ArgumentList.Add($"Import-Module '{module}' -Force; Invoke-ScriptAssystRequest -Operation '{operation}' | ConvertTo-Json -Depth 5 -Compress");
            using var process = Process.Start(psi) ?? throw new InvalidOperationException("Impossibile avviare PowerShell.");
            var output = await process.StandardOutput.ReadToEndAsync(); var error = await process.StandardError.ReadToEndAsync(); await process.WaitForExitAsync();
            if (process.ExitCode != 0) throw new InvalidOperationException(error);
            view.CoreWebView2.PostWebMessageAsJson(output.Trim());
        }
        catch (Exception ex) { view.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { error=ex.Message })); }
    }
}
