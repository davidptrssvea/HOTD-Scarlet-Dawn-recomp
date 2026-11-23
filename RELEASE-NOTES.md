# Scarlet Dawn PC v1.0.1

This release fixes package verification when Windows PowerShell cannot load its file hashing command. If the v1.0.0 updater reports that Get-FileHash is unavailable, extract the new ZIP and run setup.ps1 with the existing installation folder as -InstallDir. Setup keeps the existing settings and game data.

- Windows launcher for the supported Scarlet Dawn Export copy. Setup imports the game from your own extracted dump.
- Performance, Balanced and Quality presets, with independent Advanced Settings for the frame cap, texture pool, shadows, reflections, fog and post-processing.
- Five configurable crosshairs with size, color and preview. Original and Off modes are also available.
- Sinden border and adjustable thickness, per-player Raw Input device selection and off-screen reload.
- Corrected cursor targeting in scaled menus, including the Items screen.
- The Updates menu checks GitHub, displays release notes and installs updates after you confirm. The worker verifies the package and leaves your game and local settings in place.
- Optional support for the existing verified stereo patch when the matching files are present in your dump.

Mouse and two simulated Raw Input devices were tested through equipment selection, shooting and reload. Physical Sinden calibration remains hardware-dependent.
