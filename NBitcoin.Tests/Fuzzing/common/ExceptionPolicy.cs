using System.Text;

namespace NBitcoin.Tests.Fuzzing.Common;

internal static class ExceptionPolicy
{
	public static void Ignore(Action action, Func<Exception, bool> isExpected)
	{
		try
		{
			action();
		}
		catch (Exception ex) when (isExpected(ex))
		{
			// Expected parser failures should not abort fuzzing.
		}
	}

	public static bool IsCommonExpected(Exception ex)
	{
		return ex is FormatException
			or ArgumentException
			or OverflowException
			or EndOfStreamException
			or DecoderFallbackException;
	}

	public static bool IsAggregateExpected(Exception ex, Func<Exception, bool> leafPredicate)
	{
		if (ex is not AggregateException aggregate)
			return false;

		var flat = aggregate.Flatten();
		return flat.InnerExceptions.Count != 0 && flat.InnerExceptions.All(leafPredicate);
	}
}
