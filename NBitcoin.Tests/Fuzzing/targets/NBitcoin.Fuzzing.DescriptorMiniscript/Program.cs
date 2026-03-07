using NBitcoin;
using NBitcoin.Scripting;
using NBitcoin.Scripting.Parser;
using NBitcoin.Tests.Fuzzing.Common;
using NBitcoin.WalletPolicies;

namespace NBitcoin.Tests.Fuzzing.DescriptorMiniscript;

internal static class Program
{
	private static int Main(string[] args)
	{
		return FuzzingRunner.Run("NBitcoin.Fuzzing.DescriptorMiniscript", args, RunTarget);
	}

	private static void RunTarget(byte[] data)
	{
		if (data.Length == 0)
			return;

		foreach (var candidate in TextCandidates.BuildUtf8Candidates(
			data,
			includeHexDecode: true,
			includeBase64Decode: true,
			includeBase64AsHex: false))
		{
			ExceptionPolicy.Ignore(() => OutputDescriptor.Parse(candidate, Network.Main), IsExpected);
			ExceptionPolicy.Ignore(() => OutputDescriptor.Parse(candidate, Network.TestNet), IsExpected);
			ExceptionPolicy.Ignore(() => Miniscript.Parse(candidate, Network.Main), IsExpected);
			ExceptionPolicy.Ignore(() => Miniscript.Parse(candidate, Network.RegTest), IsExpected);
		}
	}

	private static bool IsExpected(Exception ex)
	{
		if (ExceptionPolicy.IsAggregateExpected(ex, IsExpected))
			return true;
		if (ExceptionPolicy.IsCommonExpected(ex))
			return true;
		return ex is ParsingException or MiniscriptFormatException;
	}
}
