# Case Study: `catch unreachable` and Compiler Optimization Divergence (`ReleaseFast` vs `ReleaseSmall`)

- **Related Issue**: [#32 (GitHub)](https://github.com/tsetseggames/zamgba/issues/32)
- **Target Platform**: Game Boy Advance (ARM7TDMI / Freestanding)
- **Language & Compiler**: Zig (0.16.0+) / LLVM Backend

---

## 1. Incident Summary

During the development and testing of `flappy_tsetseg_streaming.zig` (Streaming DMA Animation Demo):
- The asset's tag metadata contained `"flying"`, but the demo code called `player_anim.setAnimation("fly") catch unreachable`.
- `setAnimation("fly")` failed to match any tag and returned `error.TagNotFound`.
- **Divergent Behavior**:
  - `zig build --release=small`: The ROM booted, sprites rendered, and the sprite animated cycling through all frames. The game appeared fully functional, masking the bug.
  - `zig build --release=fast`: The ROM booted into a black screen with no sprites initialized or displayed.

---

## 2. Technical Analysis: Why `ReleaseFast` and `ReleaseSmall` Diverged

In Zig, reaching an `unreachable` statement in optimized modes (`ReleaseFast`, `ReleaseSmall`) is considered **Undefined Behavior (UB)**. The compiler assumes the code path will never be taken, but the two optimization pipelines handle this assumption very differently on bare-metal ARM targets:

```
                                  Tag lookup fails
                                          │
                                          ▼
                             ┌────────────────────────┐
                             │   error.TagNotFound    │
                             └────────────┬───────────┘
                                          │
                                 catch unreachable
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    ▼                                           ▼
      【ReleaseFast (-O3 / Speed)】                【ReleaseSmall (-Os / Size)】
  - LLVM assumes branch is dead.               - Minimizes binary code size.
  - Aggressive Dead-Code Elimination (DCE).   - Avoids aggressive block splitting/traps.
  - Strips subsequent initialization code     - Execution "falls through" or uses default state:
    or emits an ARM trap/hang.                   current_frame remains 0, animates all 8 frames.
  - Symptom: Hard crash / Black screen.        - Symptom: Silent masking / False success.
```

### 1. `ReleaseFast` Pipeline (`-O3`)
1. Reaching `unreachable` tells the LLVM optimizer that the error path is impossible.
2. In aggressive optimization passes, the optimizer infers that calling `init()` with an invalid tag name is undefined behavior.
3. LLVM may delete following instructions (dead code elimination), skip register/OAM setup, or insert an undefined instruction (`udf` / trap) which locks the ARM7TDMI CPU or puts it in an infinite exception loop before VBlank/OAM rendering starts.

### 2. `ReleaseSmall` Pipeline (`-Os`)
1. Code size optimization minimizes block duplication and avoids emitting extra trap instructions if omitting them produces a smaller binary.
2. The error return did not execute error-handling blocks, and execution fell through to the remainder of the function with `current_frame` left at its default index `0`.
3. Because DMA streaming defaults to continuous playback when no tag boundary is locked, the sprite continued to cycle through all frames (0..7), creating the illusion of working code.

---

## 3. The Danger of `catch unreachable` in Embedded Game Development

On hosted operating systems (e.g. Linux, Windows, macOS), `Debug` builds print a stack trace on panic. But on bare-metal GBA:
1. **No Default Console**: Unhandled errors or traps result in a silent hang, infinite loop, or blank screen with zero feedback.
2. **False Confidence from `ReleaseSmall`**: A bug might pass testing in `ReleaseSmall` but fail in `ReleaseFast`, leading to misleading debugging paths (such as suspecting physics, AABB, or DMA hardware timing).
3. **`catch unreachable` Abuse**: Using `catch unreachable` for inputs that depend on external strings or asset configuration (like animation tag names) turns runtime validation failures into fatal, hard-to-diagnose compiler traps.

---

## 4. Best Practices & Design Guidelines for Zamgba

To prevent similar issues in the SDK and client games:

### 1. Ban `catch unreachable` on Runtime/Asset Lookups
- Functions performing lookups (e.g., `setAnimation(tag_name)`) must return `error` or `bool`.
- Initialization routines (`init()`) must return error unions (`!Self`) and use `try`:
  ```zig
  // Recommended
  pub fn init() !Game {
      var player = try engine.AnimatedSprite.init(...);
      try player.setAnimation("flying");
      return Game{ .player = player, ... };
  }
  ```

### 2. Visual Panic & Diagnostic Channel Requirement
- When an error occurs in top-level `main()`, catch the error and route it to an immediate diagnostic handler:
  ```zig
  export fn main() noreturn {
      engine.initHardware();
      var game = Game.init() catch |err| {
          engine.debug.panic("Game.init failed: {}", .{err});
      };
      engine.run(&game);
  }
  ```
- The panic handler should:
  1. Print the error string to the mGBA debug log port (`0x04FFF780`).
  2. Optionally set a visible screen backdrop color (e.g., Red `RGB555(31, 0, 0)`) so the developer immediately knows an initialization panic occurred.
