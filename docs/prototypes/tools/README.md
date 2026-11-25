# Capture tools

These scripts drive the built prototypes with `agent-browser` (headless Chromium) and need
ImageMagick (`magick`) and `ffmpeg`. Run `python3 docs/prototypes/build.py` first. Each script
writes into `docs/prototypes/screenshots/` or `docs/prototypes/animations/`.

| Script | What it captures |
| --- | --- |
| `page.sh <name> [width]` | The whole page of any prototype in its opening state. |
| `shots-app-screens.sh [width]` | Every state of `04-app-screens`: Today, widget, Siri, public profile. |
| `shots-streak.sh [width]` | `06-streak-stakes` at several streak lengths for each option. |
| `frames-animations.sh [frames]` | A contact sheet per clip of `05-animations`, stepped with its frame slider. |
| `gifs-animations.sh [fps]` | A looping GIF per clip of `05-animations`. |

The GIFs and contact sheets step the frame slider instead of recording the screen, so every
frame is exact and the output does not depend on how fast the machine renders.
