# Scarlet Dawn PC v1.0.9 - Updater and launcher fixes

- Retry temporary Windows file replacement errors during updates and Setup. If the updater still cannot replace a file, it attempts to restore any files it already replaced and records the affected path and Windows error code in `update-error.log`.
- Show the installed builder version directly in the main menu.

Use **Updates > Download and install** from a working launcher. If the previous updater failed, close the launcher and game, extract this release's ZIP into a separate folder, and run `Setup.cmd -InstallDir "D:\Games\ScarletDawn-PC"` with your existing installation path. This keeps your game files and settings.
