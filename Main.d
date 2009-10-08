module xfbuild.Main;

private {
	version(TraceExceptions) import tango.core.stacktrace.TraceExceptions;
	
	import xfbuild.BuildTask;
	import xfbuild.Compiler : CompilerError;
	import xfbuild.GlobalParams;
	import xf.utils.Profiler;

	import tango.core.Version;
	import tango.core.ThreadPool;
	import tango.stdc.stdlib : exit;
	import tango.sys.Environment : Environment;
	import Integer = tango.text.convert.Integer;
	import tango.text.Util : split;
	import tango.util.ArgParser;
	import tango.text.json.Json;
	import tango.io.FilePath;
	import tango.io.device.File;
	import Path = tango.io.Path;
	
	import CPUid = xf.utils.CPUid;

	// TODO: better logging
	import tango.io.Stdout;
}



void printHelpAndQuit(int status) {
	Stdout(
`xfBuild 0.4 :: Copyright (C) 2009 Team0xf

Usage:
	xfbuild [--help]
	xfbuild [ROOT | OPTION | COMPILER OPTION]...
	
	Track dependencies and their changes of one or more modules, compile them
	with COMPILER OPTION(s) and link all objects into OUTPUT [see OPTION(s)].

ROOT: 
	String ended with either ".d" or "/" indicating a module
	or a directory of modules to be compiled, respectively.
	
	OPTION(s) are prefixed by "+".
	COMPILER OPTION(s) are anything that is not OPTION(s) or ROOT(s).

Recognized OPTION(s):
	+xPACKAGE    Don't compile any modules within the package
	+full        Perform a full build
	+clean       Remove object files
	+redep       Remove the dependency file
	+v           Print the compilation commands
	+h           Manage headers for faster compilation
	+profile     Dump profiling info at the end
	+modLimitNUM Compile max NUM modules at a time
	+DDEPS       Put the resulting dependencies into DEPS [default: .deps]
	+OOBJS       Put compiled objects into OBJS [default: .objs]
	+q           Use -oq when compiling (only supported by ldc)
	+noop        Don't use -op when compiling
	+nolink      Don't link
	+oOUTPUT     Link objects into the resulting binary OUTPUT
	+cCOMPILER   Use the D Compiler COMPILER [default: dmd]
	+rmo         Reverse Module Order (when compiling - might uncrash OPTLINK)
	+R           Recursively scan directories for modules
	+nodeps      Do not use dependencies' file`);
	version (MultiThreaded) Stdout(\n`	+threadsNUM  Number of theads to use [default: CPU core count]`);
	Stdout(`
	
Environment Variables:
	XFBUILDFLAGS You can put any option from above into that variable
	               Note: Keep in mind that command line options override
	                     those
	D_COMPILER   The D Compiler to use [default: dmd]
	               Note: XFBUILDFLAGS and command line options override
	                     this
`
	).flush;

	debug Stdout.formatln( "\nBuilt with {} v{} and Tango v{}.{} at {} {}\n",
		__VENDOR__, __VERSION__, Tango.Major, Tango.Minor, __DATE__, __TIME__ );

	exit(status);
}

int main(char[][] allArgs) {
	char[][] envArgs;
	
	if (Environment.get("XFBUILDFLAGS")) {
		foreach (flag; split(Environment.get("XFBUILDFLAGS"), " ")) {
			if (0 != flag.length) {
				envArgs ~= flag;
			}
		}
	}

	globalParams.compilerName = Environment.get("D_COMPILER", "dmd");
	
	if (0 == envArgs.length && 1 == allArgs.length) {
		// wrong invocation, return failure
		printHelpAndQuit(1);
	}
	
	if (2 == allArgs.length && "--help" == allArgs[1]) {
		// standard help screen
		printHelpAndQuit(0);
	}
	
	bool profiling = false;
	
	char[][] args;
	char[][] mainFiles;
	
	try {
		profile!("main")({
			FilePath[] dirsAndModules;

			foreach(arg; allArgs[1..$])
			{
				if (0 == arg.length) continue;
				
				if ('-' == arg[0]) {
					globalParams.compilerOptions ~= arg;
				} else if ('+' == arg[0]) {
					args ~= arg;
				} else {
					if ((arg == "." || arg == "./" || arg == "/" || arg.length > 2)
						&& (arg[$-2..$] == ".d" || arg[$-1] == '/')) {
							dirsAndModules ~= FilePath(arg);
					} else {
						globalParams.compilerOptions ~= arg;
					}
				}
			}
			
			auto parser = new ArgParser((char[] arg, uint) {
				throw new Exception("unknown argument: " ~ arg);
			});
			
			globalParams.threadsToUse = CPUid.coresPerCPU;
			
			bool quit	= false;
			bool removeObjs	= false;
			bool removeDeps	= false;
			
			parser.bind("+", "full",
			{
				removeObjs = true;
			});
			
			parser.bind("+", "clean",			{ removeObjs = true; quit = true; });
			parser.bind("+", "c",		(char[] arg)	{ globalParams.compilerName = arg; });
			parser.bind("+", "O",		(char[] arg)	{ globalParams.objPath = arg; });
			parser.bind("+", "D",		(char[] arg)	{ globalParams.depsPath = arg; });
			parser.bind("+", "o",		(char[] arg)	{ globalParams.outputFile = arg; });
			parser.bind("+", "x",		(char[] arg)	{ globalParams.ignore ~= arg; });
			parser.bind("+", "modLimit",	(char[] arg)	{ globalParams.maxModulesToCompile = Integer.parse(arg); });
			parser.bind("+", "redep",			{ removeDeps = true; });
			parser.bind("+", "v",				{ globalParams.verbose = globalParams.printCommands = true; });
			parser.bind("+", "profile",			{ profiling = true; });
			parser.bind("+", "h",				{ globalParams.manageHeaders = true; });
			parser.bind("+", "threads",	(char[] arg)	{ globalParams.threadsToUse = Integer.parse(arg); });
			parser.bind("+", "q",				{ globalParams.useOQ = true; });
			parser.bind("+", "noop",			{ globalParams.useOP = false; });
			parser.bind("+", "nolink",			{ globalParams.nolink = true; });
			parser.bind("+", "rmo",				{ globalParams.reverseModuleOrder = true; });
			parser.bind("+", "R",				{ globalParams.recursiveModuleScan = true; });
			parser.bind("+", "nodeps",			{ globalParams.useDeps = false; });

			// remember to parse the XFBUILDFLAGS _before_ args passed in main()
			parser.parse(envArgs);
			parser.parse(args);

			        //------------------------------------------------------------
                                void _ScanForModules (FilePath[] paths, ref char[][] modules, bool recursive = false)
                                {
                                        foreach (child; paths)
                                                if (child.exists())
                                                        if (!child.isFolder())
                                                        {
                                                                char[] filename = child.file();

                                                                if (filename.length > 2 && filename[$-2..$] == ".d")
                                                                        modules ~= child.toString().dup;
                                                        }
                                                        else
                                                                if (recursive)
                                                                        _ScanForModules (child.toList(), modules, true);
                                                else
                                                        throw new Exception("File not found: " ~ child.toString());
                                }
                                //-----------------------------------------------------------

                        _ScanForModules (dirsAndModules, mainFiles, globalParams.recursiveModuleScan);

			if ("increBuild" == globalParams.compilerName) {
				globalParams.useOP = true;
				globalParams.nolink = true;
			}
			
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
				.threadPool = new ThreadPool!(void*)(globalParams.threadsToUse);
			}
				
			{
				scope buildTask = new BuildTask(mainFiles);
				
				if(!Path.exists(globalParams.objPath))
					Path.createFolder(globalParams.objPath);

				if(removeDeps)
					Path.remove(globalParams.depsPath);

				if(removeObjs)
					buildTask.removeObjFiles();
				
				if(quit)
					return;
				
				if(mainFiles is null)
					throw new Exception("At least one MODULE needs to be specified, see +help");
					
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
	} catch (CompilerError e) {
		Stdout.formatln("Build failed: {}", e);
		return 1;
	}
}
