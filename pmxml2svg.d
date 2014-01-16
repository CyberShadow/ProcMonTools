// Convert a Process Monitor XML log to a SVG image with process timelapse

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.digest.crc;
import std.file;
import std.path;
import std.string;

import ae.utils.xml;
import ae.utils.text;
import ae.utils.time;

struct ProcessInfo
{
	string name, commandLine;
	long start, exit = long.min;
}

long getTime(XmlNode event)
{
	auto relTime = event.findChild("Relative_Time");
	if (relTime)
		return parseTime("H:i:s.u", event["Relative_Time"].text).stdTime;
	return parseTime("H:i:s.u", event["Time_of_Day"].text).stdTime;
}

ProcessInfo[] parseLog(XmlDocument xml)
{
	ProcessInfo[uint] processes;
	foreach (event; xml["procmon"]["eventlist"].children)
	{
		if (event["Operation"].text == "Process Start")
			processes[event["ProcessIndex"].text.to!uint()] = ProcessInfo(
				event["Process_Name"].text,
				event["Detail"].text.split("Command line: ")[1].split(", Current directory: ")[0],
				event.getTime()
			);
		else
		if (event["Operation"].text == "Process Exit")
			processes[event["ProcessIndex"].text.to!uint()].exit =
				event.getTime();
	}
	return processes.values;
}

string stringColor(string s)
{
	// TODO: restrict lum/sat (see ae.utils.graphics.hls)
	return "#" ~ crc32Of(s).crcHexString()[1..7];
}

auto graph(ProcessInfo[] processes)
{
	processes.sort!`a.start < b.start`();

	long first = processes[0].start;
	long last = processes.map!`a.exit`().reduce!max();

	ProcessInfo[][] rows;
	bool[string] programs;
processLoop:
	foreach (process; processes)
	{
		programs[process.name] = true;
		foreach (i, ref row; rows)
			if (!canFind!((a, b) => a.start <= b.exit && b.start <= a.exit)(row, process))
				{ row ~= process; continue processLoop; }
		rows ~= [process];
	}

	enum ROW_HEIGHT = 30;
	enum TOP = ROW_HEIGHT;
	enum LEFT = ROW_HEIGHT / 2;
	enum SECOND_WIDTH = ROW_HEIGHT * 2;
	enum TICKS_PER_PIXEL = convert!("seconds", "hnsecs")(1) / SECOND_WIDTH;
	enum MAX_TEXT_WIDTH = 200; // An estimate of how wide the legend can be

	auto seconds = (last-first).convert!("hnsecs", "seconds")() + 1;
	auto legendX = LEFT + seconds*SECOND_WIDTH + SECOND_WIDTH/2;
	auto legendTextX = legendX + ROW_HEIGHT * 3 / 4;

	auto svg = newXml().svg();
	svg.xmlns = "http://www.w3.org/2000/svg";
	svg["version"] = "1.1";
	svg.width  = text(legendTextX + MAX_TEXT_WIDTH);
	svg.height = text(TOP + max(rows.length, programs.length) * ROW_HEIGHT);

	auto grid = svg.g();
	grid.style = "stroke:rgb(200,200,200); stroke-width:2";
	foreach (y; 0..rows.length+1)
		grid.line(["x1" : text(LEFT), "y1" : text(TOP + y * ROW_HEIGHT), "x2" : text(LEFT + seconds * SECOND_WIDTH), "y2" : text(TOP + y * ROW_HEIGHT)]);
	foreach (x; 0..seconds)
		grid.line(["x1" : text(LEFT + x * SECOND_WIDTH), "y1" : text(TOP), "x2" : text(LEFT + x * SECOND_WIDTH), "y2" : text(TOP + rows.length * ROW_HEIGHT)]);

	auto labels = svg.g();
	labels.style = "text-anchor: middle; font-size: " ~ text(TOP * 3 / 4) ~ "px";
	foreach (x; 0..seconds)
	{
		auto t = labels.text(["x" : text(LEFT + x * SECOND_WIDTH), "y" : text(TOP * 3 / 4)]);
		t = text(x);
	}

	auto defs = svg.defs();
	auto grad = defs.linearGradient(["id" : "fade", "x1" : "0%", "y1" : "0%", "x2" : "0%", "y2" : "100%"]);
	grad.stop(["offset" :   "0%", "style" : "stop-color: rgb(200, 200, 200); stop-opacity: 0.5"]);
	grad.stop(["offset" : "100%", "style" : "stop-color: rgb(200, 200, 200); stop-opacity: 0"  ]);

	auto boxes = svg.g();
	foreach (y, row; rows)
		foreach (process; row)
		{
			auto g = boxes.g();
			g.title() = process.commandLine;
			auto props = ["x" : text(LEFT + (process.start-first) * 1.0 / TICKS_PER_PIXEL), "y" : text(TOP + y * ROW_HEIGHT),
				"width" : text((process.exit-process.start) * 1.0 / TICKS_PER_PIXEL), "height" : text(ROW_HEIGHT),
				"fill" : stringColor(process.name.toLower())];
			g.rect(props);
			props["fill"] = "url(#fade)";
			g.rect(props);
		}

	auto legend = svg.g();
	auto legendText = svg.g();
	legend.style = "stroke:black; stroke-width:1";
	legendText.style = "font-size: " ~ text(TOP * 3 / 4) ~ "px";
	legendText.text(["x" : text(legendX), "y" : text(ROW_HEIGHT*3/4)]) = "Legend:";

	foreach (y, program; programs.keys.sort)
	{
		auto props = ["x" : text(legendX), "y" : text(TOP + y * ROW_HEIGHT + ROW_HEIGHT*1/4),
			"width" : text(ROW_HEIGHT/2), "height" : text(ROW_HEIGHT/2),
			"fill" : stringColor(program.toLower())];
		legend.rect(props);
		props["fill"] = "url(#fade)";
		legend.rect(props);
		auto t = legendText.text(["x" : text(legendTextX), "y" : text(TOP + y * ROW_HEIGHT + ROW_HEIGHT*3/4)]);
		t = program.stripExtension();
	}

	return svg;
}

void main(string[] args)
{
	auto processes = parseLog(new XmlDocument(readText(args[1])));
	auto svg = processes.graph();
	args[1].setExtension("svg").write(svg.toString());
}
