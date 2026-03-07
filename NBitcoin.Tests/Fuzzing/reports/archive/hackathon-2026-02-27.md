# NBitcoin Fuzzing Report (Hackathon)

## Environment
- Date: 2026-02-27 04:37:24 UTC
- OS: macOS 26.2 (25C56)
- dotnet version: 10.0.102
- afl-fuzz version: 2.52b
- sharpfuzz version: sharpfuzz.commandline 2.2.0
- Target: `psbt-transaction` (primary), `descriptor-miniscript` (secondary)

## Campaign Configuration
- Budget: 2 x 45 min
- Timeout: `-t 2000+`
- Memory: `-m none`
- Input cap: `<= 1 MiB`
- Targets:
  - `psbt-transaction`
  - `descriptor-miniscript`
  - `block-message` (fallback)

## Commands Used
```powershell
# Build + instrumentation (target A)
dotnet publish /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/NBitcoin.Fuzzing.csproj -c Release -o /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-transaction
sharpfuzz /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-transaction/NBitcoin.Fuzzing.dll
sharpfuzz /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-transaction/NBitcoin.dll

# Run A
AFL_SKIP_BIN_CHECK=1 FUZZ_TARGET=psbt-transaction afl-fuzz -i /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/corpus/psbt-transaction -o /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/psbt-transaction-forksrv -m none -t 2000+ -- dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-transaction/NBitcoin.Fuzzing.dll

# Run B
AFL_SKIP_BIN_CHECK=1 FUZZ_TARGET=descriptor-miniscript afl-fuzz -i /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/corpus/descriptor-miniscript -o /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/descriptor-miniscript -m none -t 2000+ -- dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/descriptor-miniscript/NBitcoin.Fuzzing.dll

# Repro (original crash candidate)
FUZZ_TARGET=psbt-transaction dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-noinstr/NBitcoin.Fuzzing.dll /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/psbt-transaction-forksrv/crashes/id:000004,sig:02,src:000000,op:havoc,rep:128

# afl-tmin attempt (did not converge in this environment)
AFL_SKIP_BIN_CHECK=1 FUZZ_TARGET=psbt-transaction afl-tmin -x -i /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/psbt-transaction-forksrv/crashes/id:000004,sig:02,src:000000,op:havoc,rep:128 -o /tmp/psbt-transaction-id000004.min -m none -t 2000 -- dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-noinstr/NBitcoin.Fuzzing.dll

# Deterministic minimization-by-repro (final minimized case)
printf '\xFF\xFF' > /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/minimized/psbt-transaction-id000004.min
FUZZ_TARGET=psbt-transaction dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-noinstr/NBitcoin.Fuzzing.dll /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/minimized/psbt-transaction-id000004.min

# Continuation run (resume existing queues)
AFL_SKIP_BIN_CHECK=1 FUZZ_TARGET=psbt-transaction gtimeout -k 5s 600s afl-fuzz -i- -o /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/psbt-transaction-forksrv -x /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/Dictionary.txt -m none -t 2000+ -- dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-transaction/NBitcoin.Fuzzing.dll
AFL_SKIP_BIN_CHECK=1 FUZZ_TARGET=descriptor-miniscript gtimeout -k 5s 420s afl-fuzz -i- -o /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/descriptor-miniscript -x /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/Dictionary.txt -m none -t 2000+ -- dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/descriptor-miniscript/NBitcoin.Fuzzing.dll
```

## Findings Summary
| Target | Crash File | Reproduced (3/3) | Minimized File | Root Function | Status |
|---|---|---|---|---|---|
| `psbt-transaction` | `findings/psbt-transaction-forksrv/crashes/id:000004,sig:02,src:000000,op:havoc,rep:128` | Yes | `findings/minimized/psbt-transaction-id000004.min` (2 bytes) | `NBitcoin.DataEncoders.HexEncoder.IsValid` | Valid unexpected crash |
| `psbt-transaction` | `findings/psbt-transaction-forksrv/crashes/id:000015,sig:02,src:000054,op:flip4,pos:128` | Yes | Not minimized yet | `NBitcoin.Map.ThrowIfInvalidKeysLeft` | Valid unexpected crash |

## Confirmed Crash Details
### Finding 1
- Target: `psbt-transaction`
- Type: Crash
- Original input: `/Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/psbt-transaction-forksrv/crashes/id:000004,sig:02,src:000000,op:havoc,rep:128` (544 bytes)
- Minimized input: `/Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/minimized/psbt-transaction-id000004.min` (2 bytes: `ff ff`)
- Reproduction command:
```powershell
FUZZ_TARGET=psbt-transaction dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-noinstr/NBitcoin.Fuzzing.dll /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/minimized/psbt-transaction-id000004.min
```
- Stack trace:
```text
Unhandled exception. System.IndexOutOfRangeException: Index was outside the bounds of the array.
   at NBitcoin.DataEncoders.HexEncoder.IsValid(String str) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/DataEncoders/HexEncoder.cs:line 140
   at NBitcoin.DataEncoders.HexEncoder.IsWellFormed(String str) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/DataEncoders/HexEncoder.cs:line 166
   at NBitcoin.PSBT.Parse(String hexOrBase64, Network network) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/BIP174/PartiallySignedTransaction.cs:line 169
   at NBitcoin.Tests.Fuzzing.Targets.PsbtTransactionTarget.<>c__DisplayClass0_1.<Run>b__2() in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/Targets/PsbtTransactionTarget.cs:line 20
   at NBitcoin.Tests.Fuzzing.ExpectedExceptions.Ignore(Action action) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/ExpectedExceptions.cs:line 13
   at NBitcoin.Tests.Fuzzing.Targets.PsbtTransactionTarget.Run(Byte[] data) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/Targets/PsbtTransactionTarget.cs:line 18
   at NBitcoin.Tests.Fuzzing.Program.Main(String[] args) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/Program.cs:line 42
```
- Notes:
  - Crash reproduced `3/3` with the minimized input.
  - Exception type is not in whitelist.
  - `descriptor-miniscript` run finished with `0` crashes and `0` hangs.

### Finding 2
- Target: `psbt-transaction`
- Type: Crash
- Original input: `/Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/psbt-transaction-forksrv/crashes/id:000015,sig:02,src:000054,op:flip4,pos:128`
- Minimized input: Not minimized yet
- Reproduction command:
```powershell
FUZZ_TARGET=psbt-transaction dotnet /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/out/psbt-noinstr/NBitcoin.Fuzzing.dll /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/findings/psbt-transaction-forksrv/crashes/id:000015,sig:02,src:000054,op:flip4,pos:128
```
- Stack trace:
```text
Unhandled exception. System.IndexOutOfRangeException: Index was outside the bounds of the array.
   at NBitcoin.Map.ThrowIfInvalidKeysLeft() in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/BIP174/Maps.cs:line 147
   at NBitcoin.Maps.ThrowIfInvalidKeysLeft() in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/BIP174/Maps.cs:line 58
   at NBitcoin.BIP370.PSBT0..ctor(Maps maps, Network network) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/BIP174/PSBT0.cs:line 101
   at NBitcoin.PSBT.Load(Maps maps, Network network) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/BIP174/PartiallySignedTransaction.cs:line 223
   at NBitcoin.PSBT.Load(Byte[] rawBytes, Network network) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin/BIP174/PartiallySignedTransaction.cs:line 210
   at NBitcoin.Tests.Fuzzing.Targets.PsbtTransactionTarget.<>c__DisplayClass0_0.<Run>b__0() in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/Targets/PsbtTransactionTarget.cs:line 15
   at NBitcoin.Tests.Fuzzing.ExpectedExceptions.Ignore(Action action) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/ExpectedExceptions.cs:line 13
   at NBitcoin.Tests.Fuzzing.Targets.PsbtTransactionTarget.Run(Byte[] data) in /Users/thgOyo/Desktop/Dev/BitcoinFOSS/btcpay-server-projects/NBitcoin/NBitcoin.Tests/Fuzzing/Targets/PsbtTransactionTarget.cs:line 15
```
- Notes:
  - Crash reproduced `3/3` on replay.
  - Exception type is not in whitelist.

## Continuation Metrics
- `psbt-transaction-forksrv`: `execs_done=2617511`, `paths_total=201`, `unique_crashes=26`, `unique_hangs=0`
- `descriptor-miniscript`: `execs_done=421481`, `paths_total=500`, `unique_crashes=0`, `unique_hangs=0`

## Non-Finding Exceptions (Whitelist)
- `FormatException`
- `ArgumentException`
- `OverflowException`
- `EndOfStreamException`
- `DecoderFallbackException`
- `ParsingException`
- `AggregateException` (only if all inner exceptions are expected)

## Final Status
- Victory goal met (`>=1` reproducible unexpected crash): **Yes**
- Next action: Open issue/patch for `HexEncoder.IsValid` to guard non-ASCII chars before lookup (`CharToHexLookup[c]`).
