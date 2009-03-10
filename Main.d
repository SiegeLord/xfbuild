module xf.leoBuild.Main;

private {
	import xf.leoBuild.GlobalParams;
	import xf.leoBuild.BuildTask;
	import tango.util.ArgParser;

	// TODO: better logging
	import tango.io.Stdout;
}


int main(char[][] args)
{
	/+try
	{+/
		/+if(args.length < 2)
			throw new Exception("first argument needs to be the root d file");
	
		mainFile = args[1];
		
		if(!Path.exists(mainFile))
			throw new Exception("first argument needs to be the root d file");
	
		args = args[2 .. $];+/

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
		
		/+parser.bindDefault((char[] value, uint)
		{
			throw new Exception("unknown argument: " ~ value);
		});+/
		
		parser.parse(args[1..$]);
		
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
	/+}
	catch(Exception e)
	{
		Stderr("Error: ")(e).newline;
		return 1;
	}+/
	
	return 0;
}
