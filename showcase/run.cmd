@echo off
rem Plays the trailer reel: showcase\run.cmd emerald [shot number | shot name]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
