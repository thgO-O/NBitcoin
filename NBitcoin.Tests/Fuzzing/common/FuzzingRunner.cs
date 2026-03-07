using SharpFuzz;

namespace NBitcoin.Tests.Fuzzing.Common;

internal static class FuzzingRunner
{
	public static int Run(string harnessName, string[] args, Action<byte[]> target)
	{
		args ??= Array.Empty<string>();
		if (args.Length > 1)
		{
			Console.Error.WriteLine($"Usage: dotnet {harnessName}.dll [optional-input-file]");
			return 2;
		}

		if (args.Length == 1)
		{
			var reproData = File.ReadAllBytes(args[0]);
			if (reproData.Length > FuzzingInput.MaxInputBytes)
			{
				Console.Error.WriteLine($"Input '{args[0]}' is {reproData.Length} bytes, above limit {FuzzingInput.MaxInputBytes} bytes.");
				return 2;
			}

			target(reproData);
			return 0;
		}

		Fuzzer.Run(stream =>
		{
			var data = FuzzingInput.ReadBounded(stream, FuzzingInput.MaxInputBytes);
			if (data is null)
				return;
			target(data);
		});

		return 0;
	}
}
