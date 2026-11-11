# Roadmap

## Verification

- **Unit (`make test`, no permissions):** geometry, selection → pixel crop, window hit-test, file naming, settings, encoders, annotation renderer (sampled pixels with tolerance), undo stack, GIF, synthetic OCR.
- **Smoke (`make smoke`):** needs Screen Recording permission once and `defaults write local.shotx.app debugURL -bool true`. `open shotx://captureFullscreen` → newest file is a PNG of the right size; `capture-area?x&y&w&h` → exact size; start/stop a 3 s recording → MP4 longer than 2 s.

## Manual test matrix

| Area         | Case                                                                                                 | Result |
| ------------ | ---------------------------------------------------------------------------------------------------- | ------ |
| Displays     | Retina built-in display                                                                              |        |
| Displays     | Non-Retina external display                                                                          |        |
| Displays     | Two displays (secondary left of / above primary); selection on each                                  |        |
| Spaces       | Capture and overlay over a fullscreen-Space app                                                      |        |
| Permissions  | Screen Recording denied → alert with "Open System Settings"                                          |        |
| Permissions  | Screen Recording granted → survives rebuild (`make run` twice)                                       |        |
| Permissions  | Microphone denied / granted with mic recording on                                                    |        |
| Install      | `make install`, launch from `~/Applications`                                                         |        |
| Install      | Launch at login on/off survives reboot                                                               |        |
| Capture      | Area, window, fullscreen: file saved, clipboard filled, Quick Access shown                           |        |
| Capture      | Fullscreen with Quick Access cards and a pin visible: no shotX window in the image                   |        |
| Selection    | Crosshair, size label, magnifier; Esc cancels; window mode highlights the window under the cursor    |        |
| Quick Access | Cards stack; copy / save / reveal / share / annotate / pin / close; drag to Finder and to a chat app |        |
| Editor       | Every tool draws; select / move / delete; undo / redo; copied and saved output match the canvas      |        |
| Pin          | Stays on top across Spaces; aspect-locked resize; opacity                                            |        |
| Record       | MP4 and GIF, area and fullscreen, with and without audio                                             |        |
| Record       | Stopping from the system UI still saves the file                                                     |        |
| Record       | Quit shotX while recording: the MP4 is saved before the app exits                                    |        |
| Editor       | Type text, click Done / Copy / Save without Return: the text is in the output                        |        |
| Pin          | Pin a window capture: transparent corners and shadow, no grey box                                    |        |
| Settings     | Close Settings while a shortcut field waits for a key: global hotkeys still fire                     |        |
| Menu         | Every action works from the menu; while recording: red dot, timer, a single Stop item                |        |
| Settings     | Changes persist across relaunch; a hotkey change applies without restart                             |        |
| OCR          | Text from a selected area lands on the clipboard                                                     |        |
| Hotkeys      | Every default hotkey fires with another app frontmost                                                |        |

## Out of v1

Scrolling capture, cloud upload, history browser, hiding desktop icons, background/padding tool, updater, analytics, App Store distribution.
