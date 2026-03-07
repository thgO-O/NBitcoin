using NBitcoin;
using NBitcoin.Tests.Fuzzing.Common;

namespace NBitcoin.Tests.Fuzzing.BlockMessage;

internal static class Program
{
	private const int ProtocolVersion = 70015;

	private static int Main(string[] args)
	{
		return FuzzingRunner.Run("NBitcoin.Fuzzing.BlockMessage", args, RunTarget);
	}

	private static void RunTarget(byte[] data)
	{
		if (data.Length == 0)
			return;

		RunBinary(data);
		foreach (var candidate in TextCandidates.BuildUtf8Candidates(
			data,
			includeHexDecode: false,
			includeBase64Decode: true,
			includeBase64AsHex: true))
		{
			if (!TextCandidates.TryDecodeHex(candidate, out var decoded))
				continue;
			RunBinary(decoded);
		}
	}

	private static void RunBinary(byte[] bytes)
	{
		ExceptionPolicy.Ignore(() => Block.Load(bytes, Network.Main), IsExpected);
		ExceptionPolicy.Ignore(() => Block.Load(bytes, Network.TestNet), IsExpected);
		ExceptionPolicy.Ignore(() => Block.Load(bytes, Network.RegTest), IsExpected);

		ExceptionPolicy.Ignore(() => Network.Main.ParseMessage(bytes, ProtocolVersion), IsExpected);
		ExceptionPolicy.Ignore(() => Network.TestNet.ParseMessage(bytes, ProtocolVersion), IsExpected);
		ExceptionPolicy.Ignore(() => Network.RegTest.ParseMessage(bytes, ProtocolVersion), IsExpected);
	}

	private static bool IsExpected(Exception ex)
	{
		if (ExceptionPolicy.IsAggregateExpected(ex, IsExpected))
			return true;
		return ExceptionPolicy.IsCommonExpected(ex);
	}
}
