@echo off
rem workbench command for cmd.exe and PowerShell on Windows: runs bin/workbench next to
rem this file through the sh of Git for Windows (bin\sh.exe sets up Git's PATH itself).
rem Put the folder of this file into PATH to call it as  workbench  from any folder.
setlocal
set "WB_SH="
for %%G in (git.exe) do set "WB_GIT_DIR=%%~dp$PATH:G"
if defined WB_GIT_DIR (
  if exist "%WB_GIT_DIR%..\bin\sh.exe" set "WB_SH=%WB_GIT_DIR%..\bin\sh.exe"
  if exist "%WB_GIT_DIR%..\..\bin\sh.exe" set "WB_SH=%WB_GIT_DIR%..\..\bin\sh.exe"
)
if not defined WB_SH if exist "%ProgramFiles%\Git\bin\sh.exe" set "WB_SH=%ProgramFiles%\Git\bin\sh.exe"
if not defined WB_SH (
  echo workbench: sh.exe of Git for Windows not found: install Git for Windows or put git.exe into PATH 1>&2
  exit /b 1
)
rem sh splits paths on /, so the script path goes with forward slashes.
set "WB_SCRIPT=%~dp0workbench"
set "WB_SCRIPT=%WB_SCRIPT:\=/%"
"%WB_SH%" "%WB_SCRIPT%" %*
exit /b %ERRORLEVEL%
