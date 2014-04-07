import std.algorithm, std.regex, std.stdio, std.process, std.datetime, std.exception;
import core.time;
import core.sys.posix.unistd;

void main(string args[])
{
	// journalctl needs to run as root to get the full journal
	if (geteuid() != 0) {
		stderr.writeln("This program must be run as root to properly access the journal");
		return;
	}

	// Light up journalctl
	auto journalctl = pipeProcess(["journalctl", "-oshort-iso"], Redirect.stdout);

	// Create compile-time regexes to identify the start and end of a boot sequence
	enum start = ctRegex!(`Linux version`);
	enum end = ctRegex!(`Startup finished in`);

	// If there's a gap in the log longer than this duration, take note of it
	enum Duration gapSize = seconds(5);
	enum bounds = 5;

	string[] startupLines;
	bool inStartup = false;

	foreach (line; journalctl.stdout.byLine) {

		// Clear out startupLines each time we find a boot sequence
		if (match(line, start)) {
			startupLines = startupLines.init;
			inStartup = true;
		}
		// When we the end of the boot sequence, do our analysis
		else if (match(line, end)) {
			inStartup = false;

			string prev = startupLines[0];
			DateTime prevTime, currTime;

			enforce(tryGetLinesDate(prev, prevTime));

			// For each line of the log in the boot sequence, look for a gap
			foreach (i, curr; startupLines) {

				// Skip lines with no timestamp
				if (!tryGetLinesDate(curr, currTime))
					continue;

				// We found a gap
				if (prevTime + gapSize < currTime) {
					// For the lines around the gap, print them
					foreach (around; startupLines[max(i-bounds, 0) .. min(i+bounds, $)]) {
						writeln(around);
						if (around is prev)
							writeln("*GAP*");
					}
					writeln("------------------------------"); // Seperator
				}

				prev = curr;
				prevTime = currTime;

			}
		}

		// Append to startupLines if we're in a startup sequence
		if (inStartup) {
			startupLines ~= line.idup;
		}
	}
}

bool tryGetLinesDate(in string line, out DateTime dtOut)
{
	// Matches yyyy-MM-ddThh:mm:ss<TimeZone>, the ISO standard format
	enum dateMatch = ctRegex!(`(\d{4}-[01]\d-[0-3]\dT[0-2]\d:[0-5]\d:[0-5]\d)([+-][0-2]\d[0-5]\d|Z)`);

	auto dm = match(line, dateMatch);

	if (!dm)
		return false;

	dtOut = DateTime.fromISOExtString(dm.front[1]);
	return true;
}
