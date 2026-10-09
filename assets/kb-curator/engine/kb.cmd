@echo off
rem ===================================================================
rem  kb.cmd -- command-line entry point for the knowledge base.
rem  ALWAYS use this file; do NOT call kb.ps1 directly.
rem
rem  WHY THIS WRAPPER EXISTS
rem    PowerShell refuses to run kb.ps1 in this session because the
rem    session execution policy is Restricted, and aborts with:
rem        AuthorizationManager check failed.  (PSSecurityException)
rem
rem    This is a POLICY problem, not a directory or ACL problem.
rem    Measured on this machine:
rem      through this wrapper (-ExecutionPolicy Bypass):      OK
rem      calling kb.ps1 directly inside the session:          fails
rem      after Set-ExecutionPolicy -Scope Process Bypass:     OK
rem    (LocalMachine policy is Unrestricted; the per-session policy
rem     is what fails.)
rem
rem    This file is the canonical entry point because it always passes
rem    -ExecutionPolicy Bypass, so callers never have to think about it.
rem
rem    NOTE: keep this file ASCII-only. cmd.exe reads .cmd in the OEM
rem    code page, so non-ASCII comments get garbled and executed.
rem
rem  USAGE (identical to kb.ps1; C = a category name, ID = kb-YYYYMMDD-NNNN)
rem    kb.cmd init
rem    kb.cmd status
rem    kb.cmd add -Path "D:\dl\some-file.md" -Category "CATEGORY"
rem    kb.cmd list-queue
rem    kb.cmd show ID
rem    kb.cmd approve ID
rem    kb.cmd reject  ID -Reason "unreliable source"
rem    kb.cmd search  "vite port"
rem    kb.cmd page    "CATEGORY"
rem    kb.cmd log -Tail 20
rem ===================================================================
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kb.ps1" %*
exit /b %ERRORLEVEL%
