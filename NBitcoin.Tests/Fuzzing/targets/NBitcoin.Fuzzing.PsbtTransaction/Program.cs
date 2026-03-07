using NBitcoin;
using NBitcoin.Tests.Fuzzing.Common;

namespace NBitcoin.Tests.Fuzzing.PsbtTransaction;

internal static class Program
{
	private static int Main(string[] args)
	{
		return FuzzingRunner.Run("NBitcoin.Fuzzing.PsbtTransaction", args, RunTarget);
	}

	private static void RunTarget(byte[] data)
	{
		if (data.Length == 0)
			return;

		var network = Network.Main;
		ExceptionPolicy.Ignore(() => PSBT.Load(data, network), IsExpected);
		ExceptionPolicy.Ignore(() => Transaction.Load(data, network), IsExpected);

		foreach (var candidate in TextCandidates.BuildUtf8Candidates(
			data,
			includeHexDecode: true,
			includeBase64Decode: true,
			includeBase64AsHex: false))
		{
			ExceptionPolicy.Ignore(() => PSBT.Parse(candidate, network), IsExpected);
			ExceptionPolicy.Ignore(() => Transaction.Parse(candidate, network), IsExpected);
		}
	}

	private static bool IsExpected(Exception ex)
	{
		if (ExceptionPolicy.IsAggregateExpected(ex, IsExpected))
			return true;
		return ExceptionPolicy.IsCommonExpected(ex);
	}
}
