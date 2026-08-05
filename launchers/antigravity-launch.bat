@echo off
rem antigravity desktop launcher - reads marker set by switcher
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" -App antigravity -Mode desktop
