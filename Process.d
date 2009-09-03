module xf.build.Process;

private {
	import xf.build.GlobalParams;
	import tango.sys.Process;
	import Integer = tango.text.convert.Integer : toString;
	
	import tango.io.device.File;
	import tango.io.FilePath;
	import tango.text.Util;
	import tango.text.convert.Format;
	import tango.stdc.stringz;
	import tango.core.Thread;
	extern (C) extern int system(char*);
	
	// TODO: better logging
	import tango.io.Stdout;
}


class ProcessExecutionException : Exception {
	this (char[] msg) {
		super (msg);
	}
}


void checkProcessFail(Process process)
{
	auto result = process.wait();

	if(result.status != 0)
	{
		auto name = process.toString();
		
		if(name.length > 255)
			name = name[0 .. 255] ~ " [...]";
	
		throw new ProcessExecutionException(`"` ~ name ~ `" returned ` ~ Integer.toString(result.status));
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
	char[] sys = cmd.join(" ");
	char* csys = toStringz(sys);
	int ret = system(csys);
	
	if (ret != 0) {
		throw new ProcessExecutionException(`"` ~ sys ~ `" returned ` ~ Integer.toString(ret));
	}
	
	/+scope process = new Process(true, cmd);
	execute(process);
	Stderr.copy(process.stdout).flush;
	Stderr.copy(process.stderr).flush;
	checkProcessFail(process);+/
	
	
}


void executeCompilerViaResponseFile(char[] compiler, char[][] args) {
	char[] rspFile = Format("xfbuild.{:x}.rsp", cast(void*)Thread.getThis());
	File.set(rspFile, args.join("\n"));
	executeAndCheckFail([compiler, "@"~rspFile]);
	FilePath(rspFile).remove();
}
