# Local paired Simulator verification

This optional DEBUG fixture exercises two distinct app instances using native gameplay pixels, the real outgoing CV conversion, callback mailbox and canvas presenter. It substitutes a loopback raw-RGBA relay for Agora/network signaling. It does not verify Internet sharing, codec behavior, microphone capture or physical-device smoothness.

Run the relay checks without building or launching an app:

```sh
python3 PrototypeTools/paired-simulator-relay.py --self-test
```

For a manual session, start the script with `--metadata-out /tmp/bound-pair-summary.json`. Its first JSON line reports an ephemeral localhost port. Launch each already-built Simulator app with `--bound-ui-paired-transport` and `BOUND_PAIR_PEER=A` or `B`, plus `BOUND_PAIR_PORT=<port>`. Use dedicated Simulators and the original generated diagnostic cartridge; do not import personal ROMs. No account or SDK connection is used.

The relay binds only to `127.0.0.1`. It retains at most two current/stale frame buffers in memory, bounds metadata history and request concurrency, and writes only metadata JSON. Temporary HTTP request/response bodies are not a persistent pixel queue. The metadata proves a reported displayed hash/sequence came from the opposite publisher, not a screenshot placeholder. Distinct generated fixture palettes on A and B make visual provenance clearer.

`GET /control/status` returns `stage`, `orientation` per peer, online state, epoch, latest transport/UI reports and counters. `POST /control` accepts:

```json
{"stage":"landscape","orientation":{"A":"landscape","B":"landscape"}}
```

Other stages are `portrait`, `offline`, `background`, `recovered`, `done`. Set `online:false` and then `online:true` to increment the epoch and clear current frames. `delayNextPutSeconds:1.5` delays one publication ACK, without retaining a pixel backlog. After offline, `injectStaleFor:"A"` deliberately delivers one saved old-B packet only after A first receives the new epoch. Ordinary responses carry current `X-Epoch`; the deliberately stale packet carries its old `X-Epoch` and current `X-Current-Epoch`. Stale reports cannot overwrite fresh evidence.

For a full test using existing build output:

```sh
python3 PrototypeTools/paired-simulator-relay.py \
  --xctestrun /absolute/path/to/BoundCompanionQA.xctestrun \
  --sim-a <dedicated-A-UDID> --sim-b <dedicated-B-UDID> \
  --run-directory /tmp/bound-pair-run-unique \
  --metadata-out /tmp/bound-pair-summary.json
```

The runner rewrites test-root paths and assigns A/B launch environments, then runs `PairedFriendUITests.testNativeFramesAcrossLocalPeer` concurrently with `test-without-building`. It does not build, boot, install, import games or sign; prepare the two dedicated Simulators first. The default 240-second sequence is portrait, landscape, delayed in-flight ACK, offline cleared canvases, background/resume while offline, recovery with stale-frame rejection, then done. XCTest logs/result bundles live in the chosen run directory; relay output contains no pixel data. A passing result requires opposite-publisher frame hashes, both peers' UI stage reports, recovery, a stale drop and a canceled completion. Existing result bundles are not overwritten.
