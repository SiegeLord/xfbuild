module xf.build.Process;

private {
	import xf.build.GlobalParams;
	import tango.sys.Process;
	
	// TODO: better logging
	import tango.io.Stdout;
}



void checkProcessFail(Process process)
{
	auto result = process.wait();

	if(result.status != 0)
	{
		auto name = process.toString();
		
		if(name.length > 255)
			name = name[0 .. 255] ~ " [...]";
	
		throw new Exception(`"` ~ name ~ `" returned ` ~ Integer.toString(result.status));
	}
}

void execute(Process process)
{
	process.execute();
	
	if(globalParams.printCommands)
		Stdout(process).newline;
}

void executeAndCheckFail(char[][] cmd)
{
	scope process = new Process(true, cmd);
	execute(process);
	Stderr.copy(process.stdout).flush;
	Stderr.copy(process.stderr).flush;
	checkProcessFail(process);
}
