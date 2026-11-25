# Scarlet Dawn PC v1.0.11 - Automatic stereo fix generation

- Setup and the launcher now generate the complete verified stereo fix locally from your own supported Scarlet Dawn Export game data. No separate stereo patch or extra ACF files are required.
- Existing installations can generate the missing files directly from their Game folder at the next game start. The stereo fix must be enabled in Settings.
- Stereo output uses your default audio device, rather than a fixed device name.
- Switching the fix off restores the verified original audio configuration. Existing verified legacy patches remain supported.
- Source resources and generated files are checked with SHA-256 before use. Your original dump is not modified.

Update through **Updates > Download and install**, keep **Settings > Apply stereo sound fix** enabled, and restart the game. For a manual update, extract the new Local Builder ZIP, run **Setup.cmd**, and select your existing installation folder. Keep your own supported Export game data available if Setup asks for it. Your settings and local game data are retained.

Validation included generation without prepatched audio files, clean/existing Setup, stereo/original switching, cache recovery, legacy compatibility, updater regression checks, and a real-game launch with the generated patch mounted. Listening quality was not assessed.

The download contains launcher/compatibility code only. No game or audio assets are included or downloaded; the required files are generated on the user's computer from their own game data.
