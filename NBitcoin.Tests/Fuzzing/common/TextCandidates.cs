using System.Text;

namespace NBitcoin.Tests.Fuzzing.Common;

internal static class TextCandidates
{
	public static IEnumerable<string> BuildUtf8Candidates(
		byte[] bytes,
		bool includeHexDecode,
		bool includeBase64Decode,
		bool includeBase64AsHex)
	{
		var seen = new HashSet<string>(StringComparer.Ordinal);
		var utf8 = Encoding.UTF8.GetString(bytes);
		Add(utf8);
		var trimmed = utf8.Trim();
		Add(trimmed);

		if (includeHexDecode && TryDecodeHex(trimmed, out var hexBytes))
			Add(Encoding.UTF8.GetString(hexBytes));

		if (includeBase64Decode && TryDecodeBase64(trimmed, out var base64Bytes))
		{
			Add(Encoding.UTF8.GetString(base64Bytes));
			if (includeBase64AsHex)
				Add(Convert.ToHexString(base64Bytes).ToLowerInvariant());
		}

		return seen;

		void Add(string? value)
		{
			if (!string.IsNullOrWhiteSpace(value))
				seen.Add(value);
		}
	}

	public static bool TryDecodeHex(string value, out byte[] bytes)
	{
		bytes = Array.Empty<byte>();
		if (string.IsNullOrWhiteSpace(value) || (value.Length & 1) == 1)
			return false;
		try
		{
			bytes = Convert.FromHexString(value);
			return true;
		}
		catch
		{
			return false;
		}
	}

	public static bool TryDecodeBase64(string value, out byte[] bytes)
	{
		bytes = Array.Empty<byte>();
		if (string.IsNullOrWhiteSpace(value))
			return false;
		try
		{
			bytes = Convert.FromBase64String(value);
			return true;
		}
		catch
		{
			return false;
		}
	}
}
