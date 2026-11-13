Tile Burst golden dump (tileburst_golden.json).

Sources: TileBurstGoldenDump.kt (mirrors PuzzleLabTests/TileBurstGoldenTests.swift) and TileBurstOrgJsonShim.kt
(a minimal org.json stand-in; org.json was not in the offline Gradle cache). Compiled together with the
Android TileModel.kt (unchanged) and DifficultyTier/PackLevel from core/LevelPack.kt, using the cached
kotlin-compiler-embeddable 2.2.10:

  java -cp <kotlin-compiler-embeddable + deps> org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect \
       -cp kotlin-stdlib-2.2.10.jar -jvm-target 11 -d out TileModel.kt LevelPackStub.kt TileBurstOrgJsonShim.kt TileBurstGoldenDump.kt
  java -cp out:kotlin-stdlib-2.2.10.jar com.ngstudio.puzzlelab.braingames.TileBurstGoldenDumpKt

Contents: TileRNG streams, the 37 shapes (placements + weights), hypot over every half-step offset, praise
and pressure tables, bit-board helpers, rescue deals, and a TileBot play-through of all 3,000 Adventure
levels (each level's own seed), 33 Classic seeds and 61 Daily dates, folded into 64-bit FNV-1a hashes.
