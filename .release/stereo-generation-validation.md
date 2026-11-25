# Local stereo generation validation

Tested on Windows on 2026-11-25 using Windows PowerShell 5.1.

- test_stereo_generation.ps1: clean Setup from synthetic original resources without prepatched audio; stereo enable/disable; original ACF recovery without a loose backup; cache repair/reuse; legacy migration and offline fallback; rejection of corrupt sources and unknown active PAKs; saved original-audio preference retained by Setup.
- test_stereo_generation.ps1 with a private original PAK: generation/synchronization against real local exports. The credit-sound patch still generates its expected SHA-256 after sharing the export reader.
- test_stereo_import.ps1: synthetic import/Setup regression suite.
- test_stereo_import.ps1 with a private verified audio cache: legacy import/Setup checks.
- test_update_progress.ps1: updater locking, rollback, progress and cancellation.
- An isolated real-game installation began with an original loose ACF, the original main PAK and no Local/Audio or stereo PAK. Actual launcher preparation generated all three resources. A 32-second game run with audio enabled mounted the generated stereo PAK, initialized two-channel output, reached AdvertiseGameMode_C, and shut down normally with exit code 0. Listening quality was not assessed.
- Setup updated the local installation successfully and retained Settings.json byte for byte.
- The private test ZIP contains the same 19 allowlisted program/setup files as before; all manifest hashes match. No PAK, ACF, extracted Unreal resource or other game/audio asset is packaged.

Generated portable stereo PAK SHA-256:
394B7B5BAD478A259F73F57522575DA69DEF621093D087A2202431F5650ECA8D.

The recipe contains export offsets, hashes and numeric routing edits only. Original INI, ACF and Unreal resource data are read from the user's supported Export PAK. Existing verified legacy PAKs remain supported. The new INI does not pin playback to a developer's output device.

This change has not been published as a GitHub release.
