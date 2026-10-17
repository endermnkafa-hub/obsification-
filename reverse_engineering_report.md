# Comprehensive Reverse Engineering Audit: `downloaded_script.lua`

---

## 1. Executive Summary & Audit Mandate

### 1.1 Input File Verification
- **Target File Path**: `c:\Users\muhammed kılıç\Documents\antigravity\clever-davinci\downloaded_script.lua`
- **File Size**: `796,531` bytes (147 lines)
- **SHA-256**: `79b1e6618014ff6d82aa35335e85b280c99f10a604ad9062f3e7476b83ebe978`
- **Integrity**: Verified unaltered on the local filesystem.

### 1.2 Core Audit Finding: Loader vs Application Payload
Static and dynamic decompilation of `downloaded_script.lua` establishes that **the local file is exclusively an encrypted loader infrastructure (Panda Kryptic v1.4.0 over Luraph v14 Luau)**. 

The file **does not contain** the game-specific kill-farming code (`ZKSuryuFarm`) for Roblox's *The Strongest Battlegrounds* (TSB). The actual farming payload is hosted remotely on the Pandauth key-value storage service (`https://vss.pandauth.com/kv/c96fbaae7252d36e`) and delivered as AES-256-CBC encrypted network chunks only after client environment verification, hardware fingerprinting, and valid key authentication.

**Status of Deliverables**:
- `recovered_pseudocode.lua`: **Accurately represents the recovered loader logic** (VM1 Stage 1 & 2, Blocks 2 & 3, VM2 Stage 1 & 2).
- `reconstructed_farm.lua`: **Provisional, clean-room speculative implementation**. It demonstrates how a generic TSB autofarm operates under executor conventions, but **its specific functions, constants, and algorithms were NOT recovered from the local file**.

---

## 2. Coordinate System Reconciliation & Byte Ranges

Previous documentation cited varying byte counts. The table below reconciles the two distinct representations: **Source Text Coordinates** (characters in `downloaded_script.lua`) and **Decoded Binary Buffer Coordinates** (deserialized Luraph Luau VM bytecode).

### 2.1 Source Text Coordinate System (`downloaded_script.lua`)
Calculated by splitting the raw bytes on LF (`0x0A`):

| Block | Line Range | Source Text Byte Size | Cumulative Span | Description | Supporting Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Block 1** | Lines 1–4 | `161,777` bytes | `0 .. 161,777` | VM1 IIFE wrapper (`:p()`) + Luraph Base85 string literals (`[=[LPH\|...]=]`). | Verified by `raw.split(b'\n')[0:4]`. |
| **Block 2** | Lines 5–123 | `4,413` bytes | `161,777 .. 166,190` | Plaintext `Panda Key Watcher` background loop polling Pandauth. | Lines 5–123 in source. |
| **Block 3** | Lines 124–144 | `737` bytes | `166,190 .. 166,927` | Plaintext configuration defining `_G.SlugID` and `_G.PandaKrypticCfg`. | Lines 124–144 in source. |
| **Block 4** | Lines 145–147 | `629,601` bytes | `166,927 .. 796,528` | VM2 IIFE wrapper (`:o()`) + Luraph Base85 string literals + comments. | Lines 145–147 in source. |
| *Separators*| Newlines | `3` bytes | — | LF delimiter bytes. | Exact sum: `796,531` bytes. |

### 2.2 Decoded Binary Buffer Coordinate System
Luraph packs binary bytecode using custom 5-character Base85 tuples into 4 binary bytes (ratio $4/5 = 0.80$).

#### VM1 Binary Buffer (`vm1_buf.bin` — `69,880` bytes)
Decoded from Block 1 source text (`161,777` source bytes contain `~87,350` Base85 payload characters):
- **Stage 1 Bytecode (`0 .. 68,401`, 68,401 bytes)**: 1,200 constants, 48 prototypes. Root: `Proto 37`, Driver: `Proto 48`. Probes Luau recursion limits, Roblox `Path2D:GetPositionOnCurve()`, and `debug.getinfo`.
- **Stage 1 Trailing Varint & Padding (`68,401 .. 68,651`, 250 bytes)**: Varint length `52041...` and alignment padding.
- **Stage 2 Encrypted Bytecode (`68,651 .. 69,878`, 1,227 bytes)**: Decrypted via 8-byte XOR key `key1`. 61 constants, 2 prototypes (`Proto 2`, 165 instructions).
- **Trailing Pad (`69,878 .. 69,880`, 2 bytes)**: Base85 null alignment padding.

#### VM2 Binary Buffer (`vm2_buf.bin` — `430,656` bytes)
Decoded from Block 4 source text (`629,601` source bytes contain `~538,320` Base85 payload characters):
- **Stage 1 Bytecode (`0 .. 75,277`, 75,277 bytes)**: 1,208 constants, 56 prototypes. Root: `Proto 33`. Contains Luraph VM dispatch, AES-256-CBC, and string decryptor.
- **Stage 1 Trailing Varint & Padding (`75,277 .. 75,545`, 268 bytes)**: Varint length `12373...` and alignment padding.
- **Stage 2 Length Header (`75,545 .. 75,549`, 4 bytes)**: Little-endian `u32` value `1181089911` (`0x4665D877`). XORed with `1180920661` (`0x46634355`) yields exactly `355,106` bytes.
- **Stage 2 Encrypted Bytecode (`75,549 .. 430,655`, 355,106 bytes)**: Decrypted via 8-byte XOR key `key2`. 4,514 constants, 254 prototypes. Root: `Proto 162`.
- **Trailing Pad (`430,655 .. 430,656`, 1 byte)**: Base85 null pad byte.

---

## 3. Evidence Audit: Claims, Reproducibility, & Artifacts

| Claim in Report | Supporting Evidence / Exact Artifact | Classification |
| :--- | :--- | :--- |
| **Obfuscator is Luraph** | String constant `992` (`'Luraph'`) and `1119` (`"...LPH_NO_UPVALUES..."`) in `vm2_buf.bin` Stage 1 constant pool; `[=[LPH\|...]=]` tokens in source text. | **CONFIRMED** |
| **Luraph Version is v14.4+/v14.5** | Native integration of Roblox Luau `buffer` operations (`buffer.create`, `buffer.readu8`, `buffer.writeu32`), which was released in Luau in 2024; structure matches Luraph Luau v14. Specific point version (14.4 vs 14.5) is inferred from tooling signatures. | **INFERRED** |
| **VM1 Stage 2 Key (`key1`)** | Recovered via FNV-1a 64-bit hash (`Proto 38`) on telemetry buffer `c[85]` in `vm1_buf.bin`: `[0xA9, 0x45, 0xF7, 0xAC, 0x6F, 0x31, 0x0B, 0xA8]`. Validated by disassembly output in `scratch/vm1_stage2_disasm.txt`. | **CONFIRMED** |
| **VM1 Stage 2 String Decryption** | Modulo-256 LCG parameters ($a=137, c=61, xor\_k=73$) recovered directly from `Proto 28` disassembly in `scratch/disasm_vm1_stage2.py`. Decrypts `"http_spy"`, `"[Kryptic] HTTP Spy Detected..."`. | **CONFIRMED** |
| **VM2 Stage 2 Key (`key2`)** | 8-byte key `[0x1A, 0x5D, 0xD7, 0x63, 0x23, 0x79, 0x07, 0x7E]` recovered via column frequency analysis ($top\_byte \oplus 1$) in `scratch/find_xor_loop.py` and validated by successful prototype deserialization in `scratch/inspect_vm2_s2_protos.py`. | **CONFIRMED** |
| **VM2 Stage 2 Deserialization** | Exactly `4,514` constants ($read\_varint() - 81454 = 4514$) and `254` prototypes ($read\_varint() - 0x5ABD = 254$). Root proto: `Proto 162` (3,551 instrs). Pos finishes at `355,106 / 355,106` ($0$ bytes remaining). Validated in `scratch/inspect_vm2_s2_protos.py`. | **CONFIRMED** |
| **VM2 Stage 2 String Decryption** | Modulo-256 LCG parameters ($a=249, c=37, xor\_k=127$) solved via constraint propagation across 930 string constants in `scratch/solve_vm2_lcg.py`. All 930 decrypted strings saved in `scratch/vm2_stage2_strings.txt`. | **CONFIRMED** |
| **VM2 is Panda Kryptic v1.4.0 Loader** | Decrypted strings in `scratch/vm2_stage2_strings.txt` contain: `'Panda-Kryptic/1.4.0'`, `'PandaAuthV4'`, `'/keyx'`, `'/auth'`, `'ScreenGui'`, `'TweenService'`, `'main_meta — chunks:'`, `'AES-256-CBC decrypt failed'`. | **CONFIRMED** |
| **Endpoint Refusal** | Requesting `https://vss.pandauth.com/kv/c96fbaae7252d36e` without credentials returns `-- Access denied` (125 bytes, saved at `.system_generated/steps/528/content.md`). | **CONFIRMED** |
| **Game Payload Missing from File** | Zero occurrences of TSB combat remotes, damage functions, targeting algorithms, or `ZKSuryuFarm` in all 930 decrypted strings and prototype instructions across both VMs. | **CONFIRMED** |

---

## 4. Function-by-Function Audit of `reconstructed_farm.lua`

Every component of `reconstructed_farm.lua` has been evaluated against direct evidence from `downloaded_script.lua`:

| Component / Function | Original Evidence | Classification | Audit Rationale |
| :--- | :--- | :--- | :--- |
| **`Config.Enabled`** | None | **INVENTED** | Standard boilerplate execution toggle. |
| **`Config.DoServerHop`** | Contextual launcher snippet `getgenv().DoServerHop = true` | **INFERRED** | Documented in launcher context, but no reference to `DoServerHop` exists inside `downloaded_script.lua`. |
| **`Config.Targeting`** | None | **INVENTED** | `MaxTargetDistance = 1500`, `PrioritizeLowestHealth = true`, `IgnoreForceField = true`, `Whitelist` are speculative defaults. |
| **`Config.Combat`** | None | **INVENTED** | `FollowDistance = 3.5`, `AttackInterval = 0.25`, `MaxEngageDuration = 12.0` were authored from scratch based on generic autofarm heuristics. |
| **`Config.Safety`** | None | **INVENTED** | `MinSelfHealthPercent = 15` and `RespawnDelay = 1.0` have no basis in the local code. |
| **`Config.ServerHop`** | None | **INVENTED** | `TargetSearchTimeout = 10.0` and `HopCooldown = 15.0` are invented timing heuristics. |
| **`GetLocalCharacter()`** | None | **INVENTED** | Standard Luau pattern querying `LocalPlayer.Character`, `Humanoid`, and `HumanoidRootPart`. |
| **`IsPlayerAlive()`** | None | **INVENTED** | Standard check for `Humanoid.Health > 0`. |
| **`HasForceField()`** | None | **INVENTED** | Speculative spawn-protection filter (`FindFirstChildOfClass("ForceField")`). |
| **`IsRagdolled()`** | None | **INVENTED** | Speculative TSB physics state filter (`"Ragdoll"` value or `HumanoidStateType.Physics`). |
| **`FindBestTarget()`** | None | **INVENTED** | Target acquisition algorithm iterating `Players:GetPlayers()` with distance/health sorting. No targeting logic exists in the local file. |
| **`TriggerAttack()`** | None | **INVENTED** | Left mouse button click emulation via `VirtualUser:Button1Down/Up`. No attack calls or remotes were recovered. |
| **`PositionBehindTarget()`** | None | **INVENTED** | CFrame calculation positioning local character `-targetCFrame.LookVector * FollowDistance`. |
| **`ExecuteServerHop()`** | None | **INVENTED** | Clean-room query to public Roblox API `https://games.roblox.com/v1/games/%d/servers/Public` and `TeleportToPlaceInstance`. |
| **`OnHeartbeat()`** | None | **INVENTED** | Main loop bound to `RunService.Heartbeat`. |
| **`Initialize()` / Cleanup** | None | **INVENTED** | Connection tracking, `CharacterAdded` listener, and `ZKSuryuFarmRunning` watchdog loop. |

---

## 5. Distinction Between Loader Logic & Application Payload

### 5.1 What Was Actually Recovered (The Loader)
The entire client architecture of **Panda Kryptic v1.4.0** was recovered and decompiled into `recovered_pseudocode.lua`:
1. **Pre-flight Environment Validation**:
   - VM1 executes call-stack recursion and `Path2D` geometry checks.
   - Detects HTTP spies and debugging hooks, terminating with `error("[Kryptic] HTTP Spy Detected. Please Restart Roblox")`.
2. **Panda Key Watcher**:
   - Plaintext background task polling `https://api.pandauth.com/api/v1/public/getkey/pypublicfarm/status` every 600 seconds.
3. **PandaAuth License Validation & UI**:
   - Verifies HWID and key against Pandauth endpoints (`/keyx`, `/auth`, `/hello`).
   - Generates a loading interface inside `CoreGui`/`gethui` using `ScreenGui`, `UICorner`, `UIStroke`, and `TweenService`.
4. **Encrypted Network Delivery**:
   - Establishes a WebSocket (`wss://`) session with fallback to HTTP long-polling (`/http$`).
   - Receives encrypted payload chunks (`main_meta`, `main_chunk`).
   - Decrypts the reassembled stream in memory using AES-256-CBC.
   - Executes the payload via `loadstring()`.

### 5.2 What Remains Unavailable (The Application Payload)
- The actual game payload (`ZKSuryuFarm`) is **completely absent from the local file**.
- When queried without authentication, `https://vss.pandauth.com/kv/c96fbaae7252d36e` returns `-- Access denied`.
- Because server-side access controls and authentication cannot be bypassed under ethical guidelines, the exact original source code, remote event names, attack combos, and server-hopping triggers of `ZKSuryuFarm` remain unresolved.

---

## 6. List of Unresolved Questions & Limitations

1. **Undocumented Game Remotes**: Does the original `ZKSuryuFarm` use direct mouse clicks (`VirtualUser`) or does it fire specific TSB character combat `RemoteEvent` / `RemoteFunction` objects? (Unresolved: payload is server-gated).
2. **Movement Methodology**: Did the original script position players via CFrame interpolation, LinearVelocity, BodyVelocity, or pathfinding? (Unresolved).
3. **Server Hop Triggers**: Under what exact conditions did the original script trigger server hopping? (Only contextual clue is `getgenv().DoServerHop = true`).
4. **Luraph Minor Revision**: Is the compiler build specifically v14.4, v14.5, or a proprietary fork? (Unresolved: no internal patch-level tag exists).

---

## 7. Audit Conclusion

- **Bytecode & Deobfuscation Analysis**: **100% COMPLETE & VERIFIED**. Both VM1 and VM2 Stage 2 have been completely decrypted, deserialized, and mapped to the byte.
- **Loader Identification**: **CONFIRMED** as Panda Kryptic Loader v1.4.0 (`kryptic-pusl` / `PandaAuthV4`).
- **Application Logic Recovery**: **UNAVAILABLE LOCALLY**. The game farming payload was withheld by the remote Pandauth server behind key authentication.
- **`reconstructed_farm.lua` Classification**: **PROVISIONAL SPECULATIVE IMPLEMENTATION**. It provides an operational clean-room baseline for automated kill farming and server hopping, but must not be represented as the recovered original source code.
