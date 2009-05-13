module xf.build.Main;

private {
	version(TraceExceptions) import tango.core.stacktrace.TraceExceptions;
	
	import xf.build.BuildTask;
	import xf.build.Compiler : CompilerError;
	import xf.build.GlobalParams;
	import xf.utils.Profiler;

	import tango.stdc.stdlib : exit;
	import tango.sys.Environment : Environment;
	import Integer = tango.text.convert.Integer;
	import tango.text.Util : split;
	import tango.util.ArgParser;
	import tango.text.json.Json;
	import tango.io.device.File;
	import Path = tango.io.Path;
	
	import CPUid = xf.utils.CPUid;

	// TODO: better logging
	import tango.io.Stdout;
}



void printHelpAndQuit(int status) {
	Stdout(
`xfBuild 0.3 :: Copyright (C) 2009 Team0xf

Usage:
	xfbuild [-help|-clean]
	xfbuild MODULE... -oOUTPUT [OPTION]... -- [COMPILER OPTION]...

	Track dependencies and their changes of one or more MODULE(s),
	compile them with COMPILER OPTION(s) and link all objects into OUTPUT.

Options:
	-help        Show this help
	-xPACKAGE    Don't compile any modules within the package
	-full        Perform a full build
	-clean       Remove object files
	-redep       Remove the .deps file
	-v           Print the compilation commands
	-h           Manage headers for faster compilation
	-profile     Dump profiling info at the end
	-modLimitNUM Compile max NUM modules at a time
	-oOUTPUT     Put the resulting binary into OUTPUT
	-cCOMPILER   Use the D Compiler COMPILER [default: dmd0xf]`);
	version (MultiThreaded) Stdout(\n`	-threadsNUM  Number of theads to use [default: CPU core count]`);
	Stdout(`
	
Environment Variables:
	XFBUILDFLAGS You can put any option from above into that variable
	               Note: Keep in mind that command line options override
	                     those
	D_COMPILER   The D Compiler to use [default: dmd0xf]
	               Note: XFBUILDFLAGS and command line options override
	                     this
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

	globalParams.compilerName = Environment.get("D_COMPILER", "dmd0xf");
	
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
			
			globalParams.threadsToUse = CPUid.coresPerCPU;
			
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
			
			parser.bind("-", "c", (char[] arg)
			{
				globalParams.compilerName = arg;
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
			
			parser.bind("-", "h",
			{
				globalParams.manageHeaders = true;
			});

			parser.bind("-", "threads", (char[] arg)
			{
				globalParams.threadsToUse = Integer.parse(arg);
			});

			// remember to parse the XFBUILDFLAGS _before_ args passed in main()
			parser.parse(envArgs);
			parser.parse(args[1..$]);
			
			{
				if (Path.exists(globalParams.projectFile) && Path.isFile(globalParams.projectFile)) {
					scope json = new Json!(char);
					auto jobj = json.parse('{' ~ cast(char[])File.get(globalParams.projectFile) ~ '}').toObject.hashmap();
					if (auto noHeaders = "noHeaders" in jobj) {
						auto arr = (*noHeaders).toArray();
						foreach (nh; arr) {
							auto modName = nh.toString().dup;
							globalParams.noHeaders ~= modName;
						}
					}
				}
			}
			
			version (MultiThreaded) {
				.threadPool = new ThreadPoolT(globalParams.threadsToUse);
			}
				
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
