module xf.build.Main;

private {
	import tango.core.stacktrace.TraceExceptions;
	
	import xf.build.GlobalParams;
	import xf.build.BuildTask;
	import xf.build.Compiler : CompilerError;
	import tango.util.ArgParser;
	import tango.stdc.stdlib : exit;
	import Integer = tango.text.convert.Integer;
	
	import xf.utils.Profiler;

	// TODO: better logging
	import tango.io.Stdout;
	import tango.stdc.stdlib : exit;
}



void printHelpAndQuit() {
	Stdout(
`xfBuild 0.2
Copyright (C) 2009 Team0xf
Usage:
	xfbuild MainModule.d -oOutputFile { options } -- { compiler options }
	
Options:
	-Xpackage    Doesn't compile any modules within the package
	-full        Performs a full build
	-clean       Removes object files after building
	-redep       Removes the .deps file
	-v           Prints the compilation commands
	-profile     Dumps profiling info at the end
	-modLimitNUM Compile max NUM modules at a time
`
	).flush;
	exit(0);
}


void main(char[][] args) {
	if (1 == args.length) {
		printHelpAndQuit;
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
			
			parser.bind("-", "X", (char[] arg)
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
					throw new Exception("-o<filename> needs to be specified");
					
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
	} catch (CompilerError) {
		Stdout.formatln("Build failed.");
	}
}
