module xf.build.Main;

private {
	import tango.core.stacktrace.TraceExceptions;
	
	import xf.build.BuildTask;
	import xf.build.Compiler : CompilerError;
	import xf.build.GlobalParams;
	import xf.utils.Profiler;

	import tango.stdc.stdlib : exit;
	import tango.sys.Environment : Environment;
	import Integer = tango.text.convert.Integer;
	import tango.text.Util : split;
	import tango.util.ArgParser;

	// TODO: better logging
	import tango.io.Stdout;
}



void printHelpAndQuit(int status) {
	Stdout(
`xfBuild 0.2
Copyright (C) 2009 Team0xf
Usage:
	xfBuild [-help|-clean]
	xfBuild MODULE... -oOUTPUT [OPTION]... -- [COMPILER OPTION]...

	Track dependencies and their changes of one or more MODULE(s),
	compile them with COMPILER OPTION(s) and link all objects into OUTPUT.

Options:
	-help        Show this help
	-xPACKAGE    Don't compile any modules within the package
	-full        Perform a full build
	-clean       Remove object files
	-redep       Remove the .deps file
	-v           Print the compilation commands
	-profile     Dump profiling info at the end
	-modLimitNUM Compile max NUM modules at a time
	-oOUTPUT     Put the resulting binary into OUTPUT

Environment Variables:
	XFBUILDFLAGS You can put any option from above into that variable
	             Note: Keep in mind that command line options override
	                   those
`
	).flush;
	exit(status);
}

int main(char[][] args) {
	char[][] envArgs;
	
	foreach (flag; split(Environment.get("XFBUILDFLAGS"), " ")) {
		if (0 != flag.length) {
			envArgs ~= flag;
		}
	}

	if (0 == envArgs.length && 1 == args.length) {
		// wrong invocation, return failure
		printHelpAndQuit(1);
	}
	
	bool profiling = false;

	try {
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
			
			parser.bind("-", "help",
			{
				// wanted invocation, return success
				printHelpAndQuit(0);
			});
			
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
			
			parser.bind("-", "x", (char[] arg)
			{
				globalParams.ignore ~= arg;
			});

			parser.bind("-", "modLimit", (char[] arg)
			{
				globalParams.maxModulesToCompile = Integer.parse(arg);
			});

			parser.bind("-", "redep",
			{
				Path.remove(globalParams.depsPath);
			});
			
			parser.bind("-", "v",
			{
				globalParams.verbose = globalParams.printCommands = true;
			});
				
			parser.bind("-", "profile",
			{
				profiling = true;
			});

			// remember to parse the XFBUILDFLAGS _before_ args passed in main()
			parser.parse(envArgs);
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
					throw new Exception("-oOUTPUT needs to be specified, see -help");
					
				if(mainFiles is null)
					throw new Exception("At least one MODULE needs to be specified, see -help");
					
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

		return 0;
	} catch (CompilerError) {
		Stdout.formatln("Build failed.");
		return 1;
	}
}
