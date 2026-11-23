using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "scarlet-menu.ps1");
            string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            bool direct = Array.Exists(args, arg =>
                String.Equals(arg, "--no-launcher", StringComparison.OrdinalIgnoreCase) ||
                String.Equals(arg, "--skip-launcher", StringComparison.OrdinalIgnoreCase));
            bool settings = Array.Exists(args, arg => String.Equals(arg, "--settings", StringComparison.OrdinalIgnoreCase));
            string mode = direct ? " -StartMode Play" : settings ? " -StartMode Settings" : "";
            var start = new ProcessStartInfo(powershell)
            {
                Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\"" + mode,
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using (Process child = Process.Start(start)) { }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Scarlet Dawn", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
