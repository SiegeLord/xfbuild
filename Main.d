module xf.build.Main;

private {
	import xf.build.GlobalParams;
	import xf.build.BuildTask;
	import tango.util.ArgParser;
	import tango.stdc.stdlib : exit;
	
	import xf.utils.Profiler;

	// TODO: better logging
	import tango.io.Stdout;
}

void main(char[][] args) {
	try
	{
		bool profiling = false;

		profile!("main")({
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
				
			parser.bind("-", "profile",
			{
				profiling = true;
			});

			parser.parse(args[1..$]);
				
			{
				scope buildTask = new BuildTask(mainFiles);
				
				if(!Path.exists(globalParams.objPath))
					Path.createFolder(globalParams.objPath);
				
				if(removeObjs)
					buildTask.removeObjFiles();
				
				if(quit)
					return;
				
				if(globalParams.outputFile is null)
					throw new Exception("-out needs to be specified");
					
				buildTask.execute();
			}
		});
		
		if (profiling) {
			scope formatter = new ProfilingDataFormatter;
			foreach (row, col, node; formatter) {
				char[256] spaces = ' ';
				int numSpaces = node.bottleneck ? col-1 : col;
				if (numSpaces < 0) numSpaces = 0;
				Stdout.formatln("{}{}{}", node.bottleneck ? "*" : "", spaces[0..numSpaces], node.text);
			}
		}
		
		exit (0);
	}
	catch(Exception e)
	{
		Stdout(e).newline;
	}
}
