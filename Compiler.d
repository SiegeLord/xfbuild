module xfbuild.Compiler;

private {
	import xfbuild.GlobalParams;
	import xfbuild.Module;
	import xfbuild.Process;
	import xfbuild.Misc;
	import xfbuild.BuildException;

	version (MultiThreaded) {
		import xfbuild.MT;
	}

	//import xf.utils.Profiler;

	import tango.core.Exception;
	import tango.io.device.File;
	import tango.io.stream.Buffered;
	import tango.sys.Process;
	import tango.io.stream.Lines;
	import tango.text.Regex;
	import tango.util.log.Trace;
	import Path = tango.io.Path;
	import Ascii = tango.text.Ascii;

	// TODO: better logging
	import tango.io.Stdout;
}

private {
	/+Regex	importSemanticStartRegex;
	Regex	importSemanticEndRegex;+/
	//Regex	moduleSemantic1Regex;
	//Regex	verboseRegex;
}

bool isVerboseMsg(const(char)[] msg) {
	return
		msg.startsWith(`parse`)
	||	msg.startsWith(`semantic`)
	||	msg.startsWith(`function`)
	||	msg.startsWith(`import`)
	||	msg.startsWith(`library`)
	||	msg.startsWith(`code`);
}

shared static this() {
	/+importSemanticStartRegex = Regex(`^Import::semantic\('([a-zA-Z0-9._]+)'\)$`);
	importSemanticEndRegex = Regex(`^-Import::semantic\('([a-zA-Z0-9._]+)', '(.+)'\)$`);+/
	//moduleSemantic1Regex = Regex(`^semantic\s+([a-zA-Z0-9._]+)$`);
	//verboseRegex = Regex(`^parse|semantic|function|import|library|code.*`);
}



class CompilerError : BuildException {
	this (immutable(char)[] msg) {
		super (msg);
	}
    this(immutable(char)[]m,immutable(char)[]fl,long ln,Exception next=null){
        super(m,fl,ln,next);
    }
}

// TODO: Cache the escaped paths?
private char[] unescapePath(const(char)[] path) {
	char[] res = (new char[path.length])[0..0];
	for (int i = 0; i < path.length; ++i) {
		switch (path[i]) {
			case '\\': ++i;
				// fall through
			default:
//                Stdout.formatln("concatenating {}", path[i]).flush;
				res ~= path[i];
//                Stdout.formatln("done").flush;
		}
	}
	return res;
}


void compileAndTrackDeps(
		Module[] compileArray,
		ref Module[char[]] modules,
		ref Module[] compileMore,
		size_t affinity
) {
	Module getModule(const(char)[] name, const(char)[] path, bool* newlyEncountered = null) {
		Module worker() {
			if (auto mp = name in modules) {
				return *mp;
			} else {
				path = Path.standard(path.dup);
				
				// If there's a corresponding .d file, compile that instead of trying to process a .di
				if (path.length > 3 && path[$-3..$] == ".di") {
					if (Path.exists(path[0..$-1]) && Path.isFile(path[0..$-1])) {
						path = path[0..$-1];
					}
				}
				
				auto mod = new Module;
				mod.name = name.dup;
				mod.path = path;
				mod.timeModified = Path.modified(mod.path).ticks;
				assert (modules !is null);
				modules[mod.name] = mod;
				compileMore ~= mod;
				return mod;
			}
		}
		version (MultiThreaded) {
			synchronized (.threadPool) return worker();
		} else {
			return worker();
		}
	}
	
	
	const(char[])[] opts;
	
	if (globalParams.manageHeaders)
		opts ~= "-H";

	const(char)[] depsFileName;

	if (globalParams.useDeps) {
		depsFileName = compileArray[0].name ~ ".moduleDeps";
		opts ~= ["-deps=" ~ depsFileName];
	}

	if (globalParams.moduleByModule){
		foreach(mod;compileArray){
			try{
				compile(opts,[mod], (const(char)[] line) {
					if (!isVerboseMsg(line) && TextUtil.trim(line).length) {
						Stderr(line).newline;
					}
				},
						globalParams.compilerName != "increBuild", // ==moveObjects?
						affinity
					);
			} catch(ProcessExecutionException e){
				throw new CompilerError("Error compiling "~mod.name.idup,__FILE__,__LINE__,e);
			}
		}
	} else {
		try{
			compile(opts, compileArray, (const(char)[] line) {
				if (!isVerboseMsg(line) && TextUtil.trim(line).length) {
					Stderr(line).newline;
				}
			},
					globalParams.compilerName != "increBuild", // ==moveObjects?
					affinity
			       );
		} catch (ProcessExecutionException e) {
			const(char)[] mods;
			foreach(i,m;compileArray){
				if (i!=0) mods~=",";
				mods~=m.name;
			}
			throw new CompilerError("Error compiling "~mods.idup,__FILE__,
									__LINE__,e);
		}
	}

	// This must be done after the compilation so if the compiler errors out,
	// then we will keep the old deps instead of clearing them
	foreach (mod; compileArray) {
		mod.deps = null;
	}

	if (globalParams.useDeps) {
		scope depsRawFile = new File(depsFileName, File.ReadExisting);
		scope depsFile = new BufferedInput(depsRawFile);
		
		scope (exit) {
			depsRawFile.close();
			Path.remove(depsFileName);
		}

		//profile!("deps parsing")({
			foreach (line; new Lines!(char)(depsFile)) {
				auto arr = line.decomposeString(cast(char[])null, ` (`, null, `) : `, null, ` : `, null, ` (`, null, `)`, null);
				if (arr !is null && arr[0] != "object") {
					char[] modName = arr[0].dup;
					char[] modPath = unescapePath(arr[1]);

					//char[] prot = arr[2];

					if (!isIgnored(modName)) {
						assert (modPath.length > 0);
						Module m = getModule(modName, modPath);

						char[] depName = arr[3].dup;
						char[] depPath = unescapePath(arr[4]);
					
						if (depName != "object" && !isIgnored(depName)) {
							assert (depPath.length > 0);
						
							Module depMod = getModule(depName, depPath);
							//Stdout.formatln("Module {} depends on {}", m.name, depMod.name);
							m.addDep(depMod);
						}
					}
				}
			}
		//});
	}
	
	foreach (mod; compileArray) {
		mod.timeDep = mod.timeModified;
		mod.wasCompiled = true;
		mod.needRecompile = false;
		
		// remove unwanted headers
		if (!mod.isHeader) {
			auto path = mod.path;
			foreach (unwanted; globalParams.noHeaders) {
				if (unwanted == mod.name || mod.name is null) {
					if (".d" == path[$-2..$]) {
						path = path ~ "i";
						if (Path.exists(path) && Path.isFile(path)) {
							Path.remove(path);
						}
					}
				}
			}
		}
	}
}



void compile(
		const(char[])[] extraArgs,
		Module[] compileArray,
		scope void delegate(const(char)[]) stdout,
		bool moveObjects,
		size_t affinity,
) {
	void execute(const(char[])[] args, size_t affinity) {
		executeCompilerViaResponseFile(args[0], args[1..$], affinity);
		/+scope process = new Process(true, args);
		.execute(process);
		foreach(line; new Lines!(char)(process.stdout)) {
			stdout(TextUtil.trim(line));
		}

		Stderr.copy(process.stderr).flush;
		checkProcessFail(process);
		//Stdout.formatln("process finished");+/
	}
	
	if (compileArray.length)
	{
		if(!globalParams.useOP && !globalParams.useOQ)
		{
			void doGroup(Module[] group)
			{
				const(char[])[] args;

				args ~= globalParams.compilerName;
				args ~= globalParams.compilerOptions;
				args ~= "-c";
				args ~= extraArgs;

				foreach(m; group)
					args ~= m.path;

				execute(args, affinity);

				if (moveObjects) {
					foreach(m; group)
						Path.rename(m.lastName ~ globalParams.objExt, m.objFile);
				}
			}

			int[char[]] lastNames;
			Module[][] passes;

			foreach(m; compileArray)
			{
				auto lastName = cast(immutable(char)[])Ascii.toLower(m.lastName.dup);
				int group;

				if(lastName in lastNames)
					group = ++lastNames[lastName];
				else
					group = lastNames[lastName] = 0;

				if(passes.length <= group) passes.length = group + 1;
				passes[group] ~= m;
			}

			foreach(pass; passes)
			{
				if(!pass.length)
					continue;

				doGroup(pass);
			}
		}
		else
		{
			const(char[])[] args;
			args ~= globalParams.compilerName;
			args ~= globalParams.compilerOptions;
			
			if (globalParams.compilerName != "increBuild") {
				args ~= "-c";
				if (!globalParams.useOQ) {
					args ~= "-op";
				} else {
					args ~= "-oq";
					args ~= "-od" ~ globalParams.objPath;
				}
			}
			
			args ~= extraArgs;

			foreach(m; compileArray)
				args ~= m.path;
				
			auto compiled = compileArray.dup;
			
			execute(args, affinity);

			if (moveObjects) {
				if (!globalParams.useOQ) {
					try {
						foreach(m; compiled) {
							try {
								Path.rename(m.objFileInFolder, m.objFile);
							} catch (IOException) {
								// If the source file being compiled (and hence the
								// object file as well) and the object directory are
								// on different volumes, just renaming the file is an
								// invalid operation on *nix (cross-device link).
								// Hence, try copy/remove before erroring out.
								Path.copy(m.objFileInFolder, m.objFile);
								Path.remove(m.objFileInFolder);
							}
						}
					} catch (IOException e) {
						throw new CompilerError(e.msg);
					}
				}
			}
		}
	}
}


import tango.util.container.HashSet;


void compile(ref Module[char[]] modules/+, ref Module[] moduleStack+/)
{
	/+if (globalParams.verbose) {
		Stdout.formatln("compile called with: {}", modules.keys);
	}+/
	
	Module[] compileArray;
	
	//profile!("finding modules to be compiled")({
		bool[Module][Module] revDeps;
		foreach (mname, m; modules) {
			foreach (d; m.deps) {
				revDeps[d][m] = true;
			}
		}
		
		auto toCompile = new HashSet!(Module);
		{
			Module[] checkDeps;
			
			/+foreach (mod; moduleStack) {
				toCompile.add(mod);
				checkDeps ~= mod;
			}+/
			
			foreach (mname, mod; modules) {
				if (mod.needRecompile) {
					toCompile.add(mod);
					checkDeps ~= mod;
				}
			}
			
			while (checkDeps.length > 0) {
				auto mod = checkDeps[$-1];
				checkDeps = checkDeps[0..$-1];
				
				if (!(mod in revDeps)) {
					//Stdout.formatln("Module {} is not used by anything", mod.name);
				} else {
					foreach (rd, _dummy; revDeps[mod]) {
						if (!toCompile.contains(rd)) {
							toCompile.add(rd);
							checkDeps ~= rd;
						}
					}
				}
			}
		}

		compileArray = toCompile.toArray;
	
		if (globalParams.verbose) {
			Stdout.formatln("Modules to be compiled: {}", compileArray);
		}
	//});
	
	Module[] compileMore;
	
	bool firstPass = true;
	while (compileArray) {
		if (globalParams.reverseModuleOrder) {
			compileArray.reverse;
		}
		
		compileMore = null;
		
		Module[] compileNow = compileArray;
		Module[] compileLater = null;
		
		if (compileNow.length > globalParams.maxModulesToCompile) {
			compileNow = compileArray[0..globalParams.maxModulesToCompile];
			compileLater = compileArray[globalParams.maxModulesToCompile .. $];
		}
		
		//profile!("compileAndTrackDeps")({
			version (MultiThreaded) {
				int threads = globalParams.threadsToUse;

				// HACK: because affinity is stored in size_t
				// which is also what WinAPI expects;
				// TODO: do this properly one day :P
				if (threads > size_t.sizeof * 8) {
					threads = size_t.sizeof * 8;
				}
				
				Module[][] threadNow = new Module[][threads];
				Module[][] threadLater = new Module[][threads];

				foreach (th; mtFor(.threadPool, 0, threads)) {
					auto mods = compileNow[compileNow.length * th / threads .. compileNow.length * (th+1) / threads];
					if (globalParams.verbose) {
						Trace.formatln("Thread {}: compiling {} modules", th, mods.length);
					}
					
					if (mods.length > 0) {
						compileAndTrackDeps(
							mods,
							modules,
							threadLater[th],
							getNthAffinityMaskBit(th)
						);
					}
				}
				
				foreach (later; threadLater) {
					compileLater ~= later;
				}
			} else {
				Stdout("here", firstPass, modules).nl;
				compileAndTrackDeps(compileNow, modules, compileLater, size_t.max);
			}
		//});
		
		//Stdout.formatln("compileMore: {}", compileMore);
		
		auto next = compileLater ~ compileMore;
		
		/*
			In the second pass, the modules from the first one will be compiled anyway
			we'll pass them again to the compiler so it has a chance of better symbol placement
		*/
		if (firstPass && next.length > 0) {
			compileArray ~= next;
		} else {
			compileArray = next;
		}
		
		firstPass = false;
	}
}
