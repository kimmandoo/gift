Option Explicit

Dim shell, fileSystem, scriptPath, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "windows_uninstall.ps1")
command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Quote(scriptPath)
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode

Function Quote(value)
  Quote = Chr(34) & value & Chr(34)
End Function
