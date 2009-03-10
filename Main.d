module xf.leoBuild.Main;

private {
	import xf.leoBuild.GlobalParams;
	import xf.leoBuild.BuildTask;
	import tango.util.ArgParser;
	import tango.stdc.stdlib : exit;

	// TODO: better logging
	import tango.io.Stdout;
}


int main(char[][] args)
{
	foreach(i, arg; args)
	{
		if(arg == "--")
		{
			globalParams.compilerOptions ~= args[i + 1 .. $];
			args = args[0 .. i];
			break;
		}
	}
	
	char[][] mainFiles;
	
	auto parser = new ArgParser((char[] arg, uint) {
		if (arg.length > 2 && arg[$-2..$] == ".d") {
			if (Path.exists(arg)) {
				mainFiles ~= arg;
			} else {
				throw new Exception("File not found: " ~ arg);
			}
		} else {
			throw new Exception("unknown argument: " ~ arg);
		}
	});
	
	bool quit = false;
	bool removeObjs = false;
	
	parser.bind("-", "full",
	{
		removeObjs = true;
	});
	
	parser.bind("-", "clean",
	{
		removeObjs = true;
		quit = true;
	});
	
	parser.bind("-", "o", (char[] arg)
	{
		globalParams.outputFile = arg;
	});
	
	parser.bind("-", "redep",
	{
		Path.remove(".deps");
	});
	
	parser.bind("-", "v",
	{
		globalParams.verbose = globalParams.printCommands = true;
	});
		
	parser.parse(args[1..$]);
		
	{
		scope buildTask = new BuildTask(mainFiles);
		
		if(!Path.exists(globalParams.objPath))
			Path.createFolder(globalParams.objPath);
		
		if(removeObjs)
			buildTask.removeObjFiles();
		
		if(quit)
			return 0;
		
		if(globalParams.outputFile is null)
			throw new Exception("-out needs to be specified");
			
		buildTask.execute();
	}
	
	exit (0);
}
