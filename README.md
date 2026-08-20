# AURouter

AURouter is an open-source, low-latency Audio Unit patchbay for macOS. It routes a mono channel or stereo pair from a Core Audio interface through an optional chain of AUv2/AUv3 effects and sends the processed signal to any Core Audio output device.

The first release intentionally does one thing well:

```text
input channel or pair → optional Audio Unit chain → gain → output device pair
```

## Current features

- Core Audio device discovery, including live add/remove while the app is open
- Independent input and output device selection
- Explicit mono-channel or stereo-pair input selection and stereo output selection
- Automatic mono, mono-to-stereo, and stereo Audio Unit adaptation between chain slots
- Adaptive buffering, sample-rate conversion, and clock-drift correction for cross-device routes
- Crash-isolated AUv2 and AUv3 effect discovery through Apple's `auval` tool
- Ordered chain of up to eight Audio Units with per-slot bypass and plug-in UI
- Remembers the last route, effect chain, and gain; does not auto-start
- Real-time input and processed-output meters
- Output gain and panic mute
- Native SwiftUI macOS interface
- No recording or network streaming code

Same-device routes use a direct graph for the lowest latency. Cross-device routes use a dedicated input-only AUHAL and a lock-free adaptive bridge into the output graph, so an Aggregate Device is not required.

## Requirements

- macOS 14 or later
- Xcode 16 or later with the Swift toolchain
- An input device with at least one channel and a stereo output device (they may be different devices)

## Build

Build an ad-hoc-signed macOS application bundle:

```bash
./scripts/build-app.sh
open .build/AURouter.app
```

The first start of a route asks for microphone permission because macOS protects all audio input devices with that permission.

Run the test suite:

```bash
swift test
```

If SwiftPM cannot write its normal user cache in a restricted environment, use project-local caches:

```bash
env \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
  swift test \
    --cache-path "$PWD/.build/cache" \
    --config-path "$PWD/.build/config" \
    --security-path "$PWD/.build/security"
```

## Safety

Start with your interface output level turned down. A physical or software feedback loop can become loud immediately. AURouter defaults its software output gain to zero and provides a panic-mute control, but it cannot detect every external cable or mixer route.

The meter callbacks do not allocate, log, perform file I/O, or take locks. They publish levels through a small C11 atomic bridge. Graph mutations happen while routing is stopped.

## Architecture

- `AudioDeviceCatalog` reads device metadata and channel counts from the Core Audio HAL.
- `AudioRoutingEngine` hides both the direct same-device graph and the adaptive cross-device graph behind one route interface.
- `CrossDeviceAudioBridge` owns an input-only AUHAL; its callback feeds a preallocated single-producer/single-consumer stereo ring buffer.
- The output graph pulls from that ring with linear sample-rate conversion and occupancy-based clock-drift correction.
- `AudioEffectProcessScanner` enumerates plug-ins outside the host process, so a broken scanner plug-in cannot prevent the app from opening.
- Apple Matrix Mixer Audio Units select the requested hardware input, downmix stereo at −6 dB per channel when a mono plug-in requires it, duplicate mono output to stereo, and map processed stereo back to the requested output pair.
- `RouterViewModel` owns permissions and UI state on the main actor.
- `AURouterRealtime` provides lock-free atomic storage for the meters.

## Roadmap

- Saved routing profiles
- Device-disconnect and live sample-rate-change recovery
- Parallel routes and signal splits
- Generic parameter UI for plug-ins without custom views
- MIDI parameter control and scene switching

Contributions and hardware compatibility reports are welcome.
