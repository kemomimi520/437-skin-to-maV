@echo off
if exist "%~dp0runtime\pythonw.exe" (
  start "" "%~dp0runtime\pythonw.exe" "%~dp0Ma Skin Bridge.pyw" %*
) else (
  start "" pythonw "%~dp0Ma Skin Bridge.pyw" %*
)
