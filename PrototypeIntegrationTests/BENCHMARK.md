# Offline playback and sharing validation

The table below is a historical component microbenchmark, not a comparison with the original Delta app. It uses a plain view controller and changes the viewport when the panel is shown. It omits the shipping app controller, native control layout, five-second warmup, and physical presentation measurements. Do not use its mean callback interval to claim equal smoothness.

The hosted `BoundIntegrationQA` suite runs the actual VBA-M GBA bridge with an original generated cartridge, Metal GameView rendering, the companion SwiftUI panel, detached frame capture, bounded publishing, outgoing CV pixel conversion, decoded-frame mailbox and retained UIImageView canvas. The injected loopback replaces Agora's engine, codec and network. These results do not prove phone scanout, live RTC behavior, thermals or subjective smoothness.

Eight six-second samples ran all four conditions twice, with the second pass in reverse order. Full samples and logs are kept in ignored `.build/verification/latest/benchmark-summary.json` and `integration-repeated.log`.

| Panel | Capture | Mean native callback gap (ms) | p95 gap range (ms) | Largest gap (ms) | Largest p95 owner tap cost (ms) |
|---|---|---:|---:|---:|---:|
| Hidden | Off | 16.680 | 22.51–23.22 | 25.10 | 0.0062 |
| Shown | Off | 16.688 | 21.91–22.43 | 25.32 | 0.0067 |
| Hidden | On | 16.679 | 21.81–23.01 | 25.47 | 0.0262 |
| Shown | On | 16.678 | 22.21–23.05 | 25.20 | 0.0317 |

No large repeatable native-timing regression appears in these short VM samples. One earlier shown/capture sample had a 33.77 ms gap; that outlier did not repeat here, so it is neither hidden nor attributed to a particular feature. Native callback timing measures core update callbacks, not physical display presentation. Capture plus mock publication averaged roughly 28 frames/s; only one send owned resources at a time. This is not SDK throughput evidence.

A deterministic source-jitter regression exposed a capture gate flaw: resetting deadlines to each source arrival admitted 248 of 600 callbacks at 60 Hz ±0.4 ms over ten seconds. Anchored deadlines now admit approximately 300 samples, discard missed slots after stalls and preserve single-flight/epoch ownership. The sharing publisher still enforces its own publication interval.

Other passing integration checks: exact detached RGBA preservation through the actual outgoing CV pool/mailbox/canvas; changing native animation pixels arriving at the canvas; padded-plane I420 conversion; a conversion finishing after stop being rejected; slow send/recovery/background/stop fencing; malformed canvas input preserving the existing image. No account, invite or live RTC engine was used.

## App-layer audit and targeted cleanup (2026-10-06)

The original Delta app revision is `c1d3d068e019e6493eed45654569db3cc5beb86a` (2.0b5/163), DeltaCore `633dfa86967816315fe19b482511dab1ce517f28`, GBADeltaCore `869c34aeca9dd2b3fbd329092bb2743b0ae80c98`, and VBA-M `453fa0decf179360926fb417725a794aa496d6e3`. Comparison against original Git objects found all 8 GBA bridge and 197 VBA-M runtime files identical. Native audio, ring buffer, bitmap renderer, GameView and render-thread scheduling also match their pins. This establishes provenance, not performance equivalence; Bound selects Metal for GBA and adds app-layer work.

The cleanup caches decoded control placements by their actual stored bytes, computes placed-skin identifiers once, and avoids rebuilding wrappers for unchanged geometry/style/placement. It cancels the Friends UI account observer on dismissal/background while preserving the active sharing identity checks. Numeric telemetry no longer invalidates the entire companion SwiftUI view, and invisible Friend content does not present images; the bounded receive mailbox and outgoing sharing remain active. Decoded-frame sampling and SDK diagnostic dictionaries compile out of Release. Ownership-sensitive frame copies and auth checks remain unchanged pending measurements.

Tests cover external placement edits/removal, rotation, save/reset, Controller Mode, stale observer callbacks and account-owner changes, hidden presentation with ongoing publication and prompt resume, exact I420 pixels and stale conversions, and slow-send/stop recovery. A Release iPhone archive additionally verifies the sampling symbol is absent from its matching dSYM. No emulator core, audio, native scheduler, dependency pin or transport behavior was changed by this cleanup.

## Actual-controller pacing harness

`PlaybackSharingTests.testActualAppAndNativeControllerPacing` compares the native DeltaCore controller (OpenGL and Metal) with the actual Bound app controller/coordinator in Classic and Bound arrangements. The native-controller baseline is **not the complete original Delta app**. Viewport and drawable dimensions are recorded so attribution can use matched Classic geometry; the Bound arrangement is a separate shipping-layout case.

Set `BOUND_APP_PACING` to `1` in the test target’s `EnvironmentVariables` in a copy of the generated `.xctestrun`, only in an exclusive VM timing slot after compilation. The test alternates order over three repeats, using the same original fixture, pinned GBA engine, configuration, device and 1x speed, five seconds of warmup and fifteen seconds of measurement per case. `BOUND_APP_PACING=smoke` only validates the harness; its short samples are explicitly marked and are not timing evidence. The default test suite skips this opt-in test.

The harness records core callbacks including the original app callback, main-runloop wakeups, settled-layout cost and drawable observations. Its test-only wrapper observes the drawable returned by the renderer's existing `nextDrawable` call; it does not acquire an extra drawable or alter the core. The iPhone SDK supports actual presented timestamps. The Simulator SDK omits that API, so simulator results are labeled **drawable acquisitions, not presentation**. Neither callback nor acquisition counts prove displayed/unique frames. Audio underruns, input-to-display latency, GPU/energy/thermal behavior, a complete original-app comparison and real network sharing still require separate measurements. No simulator result establishes physical-phone equivalence.

The optimized smoke test passed all four controller/renderer cases. Its samples are harness validation only; no isolated timing result or original-Delta-app parity claim is recorded here.
