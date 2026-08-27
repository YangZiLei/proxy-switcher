@echo off
rem cursor desktop launcher - reads marker set by switcher
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" -App cursor -Mode desktop
