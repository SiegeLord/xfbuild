module xfbuild.Main;

private {
	version(TraceExceptions) import tango.core.tools.TraceExceptions;

	import xfbuild.MT;
	import xfbuild.BuildTask;
	import xfbuild.Compiler : CompilerError;
	import xfbuild.GlobalParams;
	import xfbuild.BuildException;
	import xfbuild.Process;

	import tango.core.Version;
	import tango.stdc.stdlib : exit;
	import tango.sys.Environment : Environment;
	import Integer = tango.text.convert.Integer;
	import tango.text.Util : split;
	//import tango.text.json.Json;
	import tango.io.FilePath;
	import tango.io.device.File;

	import Path = tango.io.Path;
	import CPUid = xfbuild.CPUid;

	// TODO: better logging
	import tango.io.Stdout;
}



void printHelpAndQuit(int status) {
	Stdout(
`xfBuild 0.5.0
http://bitbucket.org/h3r3tic/xfbuild/

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
    +x=PACKAGE      Don't compile any modules within the package
    +full           Perform a full build
    +clean          Remove object files
    +redep          Remove the dependency file
    +v              Print the compilation commands
    +h              Manage headers for faster compilation
`
//    +profile     Dump profiling info at the end
`    +mod-limit=NUM  Compile max NUM modules at a time
    +D=DEPS         Put the resulting dependencies into DEPS [default: .deps]
    +O=OBJS         Put compiled objects into OBJS [default: .objs]
    +q              Use -oq when compiling (only supported by ldc)
    +noop           Don't use -op when compiling
    +nolink         Don't link
    +o=OUTPUT       Link objects into the resulting binary OUTPUT
    +c=COMPILER     Use the D Compiler COMPILER [default: dmd]
    +C=EXT          Extension of the compiler-generated object files
                    [default: .obj on Windows, .o otherwise]
    +rmo            Reverse Module Order
                    (when compiling - might uncrash OPTLINK)
    +mbm            Module By Module, compiles one module at a time
                    (useful to debug some compiler bugs)
    +R              Recursively scan directories for modules
    +nodeps         Don't use dependencies' file
    +keeprsp        Don't remove .rsp files upon errors`);
	version (MultiThreaded) {

		Stdout.formatln(`

Multithreading options:
    +threads=NUM           Number of theads to use [default: CPU core count]
    +no-affinity           Do NOT manage process affinity (New feature which
                           should prevent DMD hanging on multi-core systems)
    +linker-affinity=MASK  Process affinity mask for the linker
                           (hexadecimal) [default: {:x} (OS-dependent)]`,
			globalParams.linkerAffinityMask
		);

	}

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


// the olde arg parser in Tango got deprecated and the new one is too
// fancy for our purposes so here's a quickly whipped up one :P
struct ArgParser {
	void delegate(char[]) err;
	struct Reg {
		char[] t;
		void delegate() a;
		void delegate(char[]) b;
	}
	Reg[] reg;
	void bind(char[] t, void delegate() a) {
		reg ~= Reg(t.dup, a, null);
	}
	void bind(char[] t, void delegate(char[]) b) {
		reg ~= Reg(t.dup, null, b);
	}
	void parse(char[][] args) {
		argIter: foreach (arg; args) {
			if (0 == arg.length) continue;
			if (arg[0] != '+') {
				err(arg);
				continue;
			}
			arg = arg[1..$];
			foreach (r; reg) {
				if (r.t.length <= arg.length && r.t == arg[0..r.t.length]) {
					if (r.a !is null) r.a();
					else r.b(arg[r.t.length..$]);
					continue argIter;
				}
			}
			err(arg);
		}
	}
}


void determineSystemSpecificOptions() {
	version (Windows) {
		/* Walter has admitted to OPTLINK having issues with threading */
		globalParams.linkerAffinityMask = getNthAffinityMaskBit(0);
	}
}


int main(char[][] allArgs) {
	determineSystemSpecificOptions();


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
		//profile!("main")({
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
			
			auto parser = ArgParser((char[] arg) {
				throw new Exception("unknown argument: " ~ arg);
			});
			
			globalParams.threadsToUse = CPUid.coresPerCPU;
			
			bool quit	= false;
			bool removeObjs	= false;
			bool removeDeps	= false;

			// support for the olde arg style where they didn't have to be
			// preceded with an equal sign
			char[] olde(char[] arg) {
				if (arg.length > 0 && '=' == arg[0]) {
					return arg[1..$];
				} else {
					return arg;
				}
			}
			
			parser.bind("full",                     { removeObjs = true; });
			parser.bind("clean",			        { removeObjs = true; quit = true; });
			parser.bind("c",		(char[] arg)	{ globalParams.compilerName = olde(arg); });
			parser.bind("C",		(char[] arg)	{ globalParams.objExt = olde(arg); });		// HACK: should use profiles/configs instead
			parser.bind("O",		(char[] arg)	{ globalParams.objPath = olde(arg); });
			parser.bind("D",		(char[] arg)	{ globalParams.depsPath = olde(arg); });
			parser.bind("o",		(char[] arg)	{ globalParams.outputFile = olde(arg); });
			parser.bind("x",		(char[] arg)	{ globalParams.ignore ~= olde(arg); });
			parser.bind("modLimit",	(char[] arg)	{ globalParams.maxModulesToCompile = cast(int)Integer.parse(olde(arg)); });
			parser.bind("mod-limit=",	(char[] arg){ globalParams.maxModulesToCompile = cast(int)Integer.parse(arg); });
			parser.bind("redep",			        { removeDeps = true; });
			parser.bind("v",				        { globalParams.verbose = globalParams.printCommands = true; });
			//parser.bind("profile",			        { profiling = true; });
			parser.bind("h",				        { globalParams.manageHeaders = true; });
			
			parser.bind("threads",	(char[] arg)	{ globalParams.threadsToUse = cast(int)Integer.parse(olde(arg)); });
			parser.bind("no-affinity",				{ globalParams.manageAffinity = false; });
			parser.bind("linker-affinity=",	(char[] arg){ globalParams.linkerAffinityMask = cast(size_t)Integer.parse(olde(arg), 16); });
			
			parser.bind("q",				        { globalParams.useOQ = true; });
			parser.bind("noop",			            { globalParams.useOP = false; });
			parser.bind("nolink",			        { globalParams.nolink = true; });
			parser.bind("rmo",			        	{ globalParams.reverseModuleOrder = true; });
			parser.bind("mbm",			        	{ globalParams.moduleByModule = true; });
			parser.bind("R",			        	{ globalParams.recursiveModuleScan = true; });
			parser.bind("nodeps",		        	{ globalParams.useDeps = false; });
			parser.bind("keeprsp",		        	{ globalParams.removeRspOnFail = false; });

			// remember to parse the XFBUILDFLAGS _before_ args passed in main()
			parser.parse(envArgs);
			parser.parse(args);

			        //------------------------------------------------------------
                    void _ScanForModules (FilePath[] paths, ref char[][] modules, bool recursive = false, bool justCheckAFolder = false) {
                            foreach (child; paths) {
                                    if (child.exists()) {
                                            if (!child.isFolder()) {
                                                    char[] filename = child.file();

                                                    if (filename.length > 2 && filename[$-2..$] == ".d") {
                                                            modules ~= child.toString().dup;
                                                    }
                                            } else {
                                                    if (recursive) {
                                                            _ScanForModules (child.toList(), modules, true);
                                                    } else {
                                                            if( !justCheckAFolder ) {
                                                                    _ScanForModules (child.toList(), modules, false, true);
                                                            }
                                                    }
                                            }
                                    } else {
                                            throw new Exception("File not found: " ~ child.toString());
                                    }
                            }
                    }
                    //-----------------------------------------------------------

            _ScanForModules (dirsAndModules, mainFiles, globalParams.recursiveModuleScan);

			if ("increBuild" == globalParams.compilerName) {
				globalParams.useOP = true;
				globalParams.nolink = true;
			}
			
			/+{
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
			}+/
			
			version (MultiThreaded) {
				.threadPool = new ThreadPoolT(globalParams.threadsToUse);
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
					return 0;
				
				if(mainFiles is null)
					throw new Exception("At least one MODULE needs to be specified, see +help");
					
				buildTask.execute();
			}
		//});
		
		/+if (profiling) {
			scope formatter = new ProfilingDataFormatter;
			foreach (row, col, node; formatter) {
				char[256] spaces = ' ';
				int numSpaces = node.bottleneck ? col-1 : col;
				if (numSpaces < 0) numSpaces = 0;
				Stdout.formatln("{}{}{}", node.bottleneck ? "*" : "", spaces[0..numSpaces], node.text);
			}
		}+/

		return 0;
	} catch (BuildException e) {
		Stdout.formatln("Build failed: {}", e);
		return 1;
	}
}
