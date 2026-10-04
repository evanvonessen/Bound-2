# Offline playback and sharing validation

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
