Option Explicit

Dim shell, files, root, payloadPath, scriptPath, command
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
root = files.GetParentFolderName(WScript.ScriptFullName)
payloadPath = files.BuildPath(root, "gift-runtime.zip")
scriptPath = files.BuildPath(root, "Install-Gift.ps1")

If Not files.FileExists(scriptPath) Or Not files.FileExists(payloadPath) Then
    MsgBox "Install-Gift.ps1 or gift-runtime.zip is missing from the setup package.", 16, "GIFT Setup"
    WScript.Quit 1
End If

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(scriptPath) & " -PayloadPath " & Quote(payloadPath)
shell.Run command, 0, False

Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function

