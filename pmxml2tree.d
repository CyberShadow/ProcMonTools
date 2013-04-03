// Parse a Process Monitor XML log and print a "tree" of created processes.
// Assumes processes start/stop strictly in sequence.

import ae.utils.xml;
import ae.utils.text;
import std.array;
import std.file;
import std.stdio;
import std.string;

void main(string[] args)
{
	auto xml = new XmlDocument(readText(args[1]));
	int indent = 0;
	string lastEvent;
	foreach (event; xml["procmon"]["eventlist"].children)
	{
		if (event["Operation"].text == "Process Start")
			writefln("%s\t%s%s", event["Relative_Time"].text, "  ".replicate(indent++),
				event["Detail"].text.split("Command line: ")[1].split(", Current directory: ")[0]);
		else
		if (event["Operation"].text == "Process Exit")
			indent--, lastEvent = event["Relative_Time"].text;
	}
	writefln("%s\t%s", lastEvent, "-- END --");
}
