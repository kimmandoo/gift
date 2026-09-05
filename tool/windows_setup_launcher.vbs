Option Explicit

Dim shell, fileSystem, scriptDirectory, payloadPath, launcherPath, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
payloadPath = fileSystem.BuildPath(scriptDirectory, "payload.zip")
launcherPath = fileSystem.BuildPath(scriptDirectory, "windows_setup_launcher.ps1")
command = "powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File " _
  & Quote(launcherPath) & " -PayloadPath " & Quote(payloadPath)

exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode

Function Quote(value)
  Quote = Chr(34) & value & Chr(34)
End Function
