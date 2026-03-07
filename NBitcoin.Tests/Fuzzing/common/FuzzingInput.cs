namespace NBitcoin.Tests.Fuzzing.Common;

internal static class FuzzingInput
{
	public const int MaxInputBytes = 1024 * 1024;

	public static byte[]? ReadBounded(Stream stream, int maxBytes)
	{
		using var ms = new MemoryStream();
		var buffer = new byte[8192];
		while (true)
		{
			var read = stream.Read(buffer, 0, buffer.Length);
			if (read <= 0)
				break;

			if (ms.Length + read > maxBytes)
				return null;

			ms.Write(buffer, 0, read);
		}

		return ms.ToArray();
	}
}
