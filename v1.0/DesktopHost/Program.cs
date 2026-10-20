using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace DashboardAD.Desktop;

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
    private readonly string root = AppContext.BaseDirectory;
    private readonly string sessionId = Guid.NewGuid().ToString("N");
    private readonly DateTimeOffset sessionStartedLocal = DateTimeOffset.Now;
    private string? sessionLogPath;
    private bool sessionEndLogged;

    private static readonly HashSet<string> AllowedOperations = new(StringComparer.Ordinal)
    {
        "status", "dashboard", "users", "groups", "ous", "createOU", "updateOU", "deleteOU", "gpos", "tasks", "disableUser", "enableUser", "moveUser", "resetPassword", "deleteUser", "userDetails", "createUser", "updateUser", "copyUser", "createGroup", "deleteGroup", "groupDeletePreview", "updateGroup", "groupMembers", "updateGroupMembers", "searchDirectoryMembers", "updateUserGroups", "ouContents", "availableGroups", "readLogs"
    };

    public MainForm()
    {
        Text = "Dashboard AD v1.0";
        Width = 1280;
        Height = 820;
        MinimumSize = new Size(900, 620);
        Controls.Add(view);
        Load += async (_, _) => await InitializeViewAsync();
        FormClosing += (_, _) =>
        {
            if (sessionEndLogged) return;
            sessionEndLogged = true;
            WriteAuditEvent("session_end", sessionId, true, null, null);
        };
    }

    private async Task InitializeViewAsync()
    {
        sessionLogPath = CreateSessionLogPath();
        WriteAuditEvent("session_start", sessionId, true, null, null);
        await view.EnsureCoreWebView2Async();
        view.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
        var page = Path.Combine(root, "UI", "index.html");
        if (!File.Exists(page))
        {
            MessageBox.Show($"Interfaccia non trovata: {page}", "Dashboard AD");
            Close();
            return;
        }
        view.Source = new Uri(page);
    }

    private string GetConfiguredLogPath()
    {
        var configPath = Path.Combine(root, "DashboardAD.config.json");
        using var config = JsonDocument.Parse(File.ReadAllText(configPath, Encoding.UTF8));
        var configured = config.RootElement.GetProperty("Logging").GetProperty("Path").GetString();
        if (string.IsNullOrWhiteSpace(configured))
            throw new InvalidOperationException("Logging.Path non è configurato.");
        return Environment.ExpandEnvironmentVariables(configured);
    }

    private string GetOperatorName()
    {
        return string.IsNullOrWhiteSpace(Environment.UserDomainName)
            ? Environment.UserName
            : Environment.UserDomainName + "\\" + Environment.UserName;
    }

    private string CreateSessionLogPath()
    {
        var configuredPath = GetConfiguredLogPath();
        var directory = Path.GetDirectoryName(configuredPath) ?? root;
        var stem = Path.GetFileNameWithoutExtension(configuredPath);
        var extension = Path.GetExtension(configuredPath);
        var operatorToken = string.Concat(GetOperatorName().Select(ch =>
            ch == '\\' || ch == '/' || Path.GetInvalidFileNameChars().Contains(ch) ? '-' : ch));
        operatorToken = operatorToken.Trim(' ', '.', '-');
        if (string.IsNullOrWhiteSpace(operatorToken)) operatorToken = "unknown-operator";
        var stamp = sessionStartedLocal.ToString("yyyyMMdd-HHmmss-fff");
        var path = Path.Combine(directory, $"{stem}_{operatorToken}_{stamp}{extension}");
        var suffix = 1;
        while (File.Exists(path))
            path = Path.Combine(directory, $"{stem}_{operatorToken}_{stamp}-{suffix++}{extension}");
        return path;
    }

    private string GetSessionLogPath() => sessionLogPath ??= CreateSessionLogPath();

    private int GetConfiguredMaxLogSizeMb()
    {
        try
        {
            using var config = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "DashboardAD.config.json"), Encoding.UTF8));
            if (config.RootElement.GetProperty("Logging").TryGetProperty("MaxLogSizeMB", out var size) &&
                size.TryGetInt32(out var value) && value > 0)
                return value;
        }
        catch { }
        return 2;
    }

    private void WriteAuditEvent(string action, string target, bool success, string? error, string? adminAccount)
    {
        try
        {
            var logPath = GetSessionLogPath();
            var directory = Path.GetDirectoryName(logPath);
            if (!string.IsNullOrWhiteSpace(directory))
                Directory.CreateDirectory(directory);

            string? controller = null;
            try
            {
                using var config = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "DashboardAD.config.json"), Encoding.UTF8));
                // La sessione viene registrata prima della connessione AD: non attribuire un controller non ancora verificato.
                adminAccount ??= config.RootElement.GetProperty("ActiveDirectory").GetProperty("ExpectedAdminUsername").GetString();
            }
            catch { }

            var record = new
            {
                timestamp = DateTimeOffset.UtcNow.ToString("O"),
                eventType = action.StartsWith("session_", StringComparison.Ordinal) ? "session" : "application",
                sessionId,
                @operator = string.IsNullOrWhiteSpace(Environment.UserDomainName)
                    ? Environment.UserName
                    : Environment.UserDomainName + "\\" + Environment.UserName,
                adminAccount = adminAccount ?? "",
                sourceComputer = Environment.MachineName,
                domainController = controller ?? "",
                action,
                target,
                success,
                error = success ? null : error,
                ticket = (string?)null
            };
            var line = JsonSerializer.Serialize(record);
            var bytes = Encoding.UTF8.GetByteCount(line + Environment.NewLine);
            var maxBytes = (long)GetConfiguredMaxLogSizeMb() * 1024 * 1024;
            var info = new FileInfo(logPath);
            // Un file per sessione non viene ruotato: avvio, modifiche e chiusura restano insieme.
            if (sessionLogPath is null && info.Exists && info.Length + bytes > maxBytes)
            {
                var stem = Path.GetFileNameWithoutExtension(logPath);
                var extension = Path.GetExtension(logPath);
                var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss-fff");
                var rotatedPath = Path.Combine(directory ?? root, $"{stem}-{stamp}{extension}");
                var suffix = 1;
                while (File.Exists(rotatedPath))
                    rotatedPath = Path.Combine(directory ?? root, $"{stem}-{stamp}-{suffix++}{extension}");
                File.Move(logPath, rotatedPath);
            }
            File.AppendAllText(logPath, line + Environment.NewLine, new UTF8Encoding(false));
        }
        catch { }
    }

    private string ReadAuditLogsResponse()
    {
        var configuredPath = GetConfiguredLogPath();
        var directory = Path.GetDirectoryName(configuredPath) ?? root;
        var logPath = GetSessionLogPath();
        var stem = Path.GetFileNameWithoutExtension(logPath);
        var extension = Path.GetExtension(logPath);
        var paths = Directory.Exists(directory)
            ? Directory.GetFiles(directory, stem + "*" + extension).OrderByDescending(File.GetLastWriteTimeUtc).ToArray()
            : Array.Empty<string>();
        var files = new List<object>();
        foreach (var file in paths)
        {
            var info = new FileInfo(file);
            var records = new List<JsonElement>();
            foreach (var line in File.ReadLines(file, Encoding.UTF8))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try { using var parsed = JsonDocument.Parse(line); records.Add(parsed.RootElement.Clone()); }
                catch { }
            }
            files.Add(new {
                name = info.Name,
                active = string.Equals(Path.GetFullPath(file), Path.GetFullPath(logPath), StringComparison.OrdinalIgnoreCase),
                lastWriteUtc = info.LastWriteTimeUtc.ToString("O"),
                sizeBytes = info.Length,
                eventCount = records.Count,
                records
            });
        }
        return JsonSerializer.Serialize(new { success = true, operation = "readLogs", data = new { activeFile = Path.GetFileName(logPath), files }, error = (string?)null });
    }

    private async void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string? operation = null;
        try
        {
            using var message = JsonDocument.Parse(e.WebMessageAsJson);
            if (!message.RootElement.TryGetProperty("operation", out var operationElement))
                throw new InvalidOperationException("Richiesta priva dell'operazione.");
            operation = operationElement.GetString();
            if (operation is null || !AllowedOperations.Contains(operation))
                throw new InvalidOperationException("Operazione non consentita.");

            if (operation == "readLogs")
            {
                view.CoreWebView2.PostWebMessageAsJson(ReadAuditLogsResponse());
                return;
            }

            var query = "";
            if (message.RootElement.TryGetProperty("query", out var queryElement))
            {
                if (queryElement.ValueKind != JsonValueKind.String)
                    throw new InvalidOperationException("Il parametro query deve essere testuale.");
                query = queryElement.GetString() ?? "";
                if (query.Length > 128)
                    throw new InvalidOperationException("Il parametro query supera 128 caratteri.");
            }

            var script = Path.Combine(root, "Backend", "Start-DashboardAD.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Backend PowerShell non trovato.", script);

            var psi = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                RedirectStandardInput = true,
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
            psi.ArgumentList.Add("-ReadRequestFromStdin");
            psi.Environment["DASHBOARDAD_SESSION_LOG_PATH"] = GetSessionLogPath();
            psi.Environment["DASHBOARDAD_SESSION_ID"] = sessionId;

            using var process = Process.Start(psi) ?? throw new InvalidOperationException("Impossibile avviare PowerShell.");
            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();

            // PowerShell può terminare prima di leggere la richiesta. In quel caso
            // WriteAsync genera "The pipe is being closed": attendiamo comunque il
            // processo per recuperare stderr e il vero errore del backend.
            IOException? stdinWriteError = null;
            try
            {
                await process.StandardInput.WriteAsync(e.WebMessageAsJson);
            }
            catch (IOException ex)
            {
                stdinWriteError = ex;
            }
            finally
            {
                try { process.StandardInput.Close(); }
                catch (IOException) { }
            }

            await process.WaitForExitAsync();
            var output = await outputTask;
            var error = await errorTask;

            if (process.ExitCode != 0)
            {
                var details = string.IsNullOrWhiteSpace(error)
                    ? $"Backend PowerShell terminato con codice {process.ExitCode}."
                    : error.Trim();
                throw new InvalidOperationException(details);
            }

            if (string.IsNullOrWhiteSpace(output))
            {
                var details = !string.IsNullOrWhiteSpace(error)
                    ? error.Trim()
                    : stdinWriteError is not null
                        ? $"PowerShell ha chiuso lo standard input prima di restituire una risposta: {stdinWriteError.Message}"
                        : "Il backend non ha restituito dati.";
                throw new InvalidOperationException(details);
            }

            view.CoreWebView2.PostWebMessageAsJson(output.Trim());
        }
        catch (Exception ex)
        {
            view.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { success = false, operation, data = (object?)null, error = ex.Message }));
        }
    }
}