module xfbuild.Compiler;

private {
	import xfbuild.GlobalParams;
	import xfbuild.Module;
	import xfbuild.Process;
	import xfbuild.Misc;
	
	version (MultiThreaded) {
		import xfbuild.MT;
	}

	import xf.utils.Profiler;

	import tango.io.device.FileMap;
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

bool isVerboseMsg(char[] msg) {
	return
		msg.startsWith(`parse`)
	||	msg.startsWith(`semantic`)
	||	msg.startsWith(`function`)
	||	msg.startsWith(`import`)
	||	msg.startsWith(`library`)
	||	msg.startsWith(`code`);
}

static this() {
	/+importSemanticStartRegex = Regex(`^Import::semantic\('([a-zA-Z0-9._]+)'\)$`);
	importSemanticEndRegex = Regex(`^-Import::semantic\('([a-zA-Z0-9._]+)', '(.+)'\)$`);+/
	//moduleSemantic1Regex = Regex(`^semantic\s+([a-zA-Z0-9._]+)$`);
	//verboseRegex = Regex(`^parse|semantic|function|import|library|code.*`);
}



class CompilerError : Exception {
	this (char[] msg) {
		super (msg);
	}
}


private char[] unescapePath(char[] path) {
	char[] res = (new char[path.length])[0..0];
	for (int i = 0; i < path.length; ++i) {
		switch (path[i]) {
			case '\\': ++i;
				// fall through
			default:
				res ~= path[i];
		}
	}
	return res;
}


void compileAndTrackDeps(Module[] compileArray, ref Module[char[]] modules, ref Module[] compileMore)
{
	Module getModule(char[] name, char[] path, bool* newlyEncountered = null) {
		Module worker() {
			if (auto mp = name in modules) {
				return *mp;
			} else {
				path = Path.standard(path);
				
				// If there's a corresponding .d file, compile that instead of trying to process a .di
				if (path.length > 3 && path[$-3..$] == ".di") {
					if (Path.exists(path[0..$-1]) && Path.isFile(path[0..$-1])) {
						path = path[0..$-1];
					}
				}
				
				auto mod = new Module;
				mod.name = name.dup;
				mod.path = path.dup;
				mod.timeModified = Path.modified(mod.path).ticks;
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
	
	
	final depsFileName = compileArray[0].name~".moduleDeps";
	try {
		char[][] opts;
		if (globalParams.manageHeaders) {
			opts ~= "-H";
		}
		
		compile(opts ~ ["-deps="~depsFileName], compileArray, (char[] line) {
			if(!isVerboseMsg(line) && TextUtil.trim(line).length)
				Stderr(line).newline;
		},
			globalParams.compilerName != "increBuild" // ==moveObjects?
		);
	} catch (ProcessExecutionException e) {
		throw new CompilerError(e.msg);
	}

	// This must be done after the compilation so if the compiler errors out,
	// then we will keep the old deps instead of clearing them
	foreach (mod; compileArray) {
		mod.deps = null;
	}
	
	scope depsFile = new FileMap(depsFileName);
	scope(exit) {
		depsFile.close();
		Path.remove(depsFileName);
	}

	//profile!("deps parsing")({
		foreach (line; new Lines!(char)(depsFile)) {
			auto arr = line.decomposeString(cast(char[])null, ` (`, null, `) : `, null, ` : `, null, ` (`, null, `)`, null);
			if (arr !is null) {
				char[] modName = arr[0].dup;
				char[] modPath = unescapePath(arr[1].dup);

				//char[] prot = arr[2];
				
				if (!isIgnored(modName)) {
					assert (modPath.length > 0);
					Module m = getModule(modName, modPath);

					char[] depName = arr[3].dup;
					char[] depPath = unescapePath(arr[4].dup);
					
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
		char[][] extraArgs,
		Module[] compileArray,
		void delegate(char[]) stdout,
		bool moveObjects
) {
	void execute(char[][] args) {
		executeCompilerViaResponseFile(args[0], args[1..$]);
		/+scope process = new Process(true, args);
		.execute(process);
		foreach(line; new Lines!(char)(process.stdout)) {
			stdout(TextUtil.trim(line));
		}

		Stderr.copy(process.stderr).flush;
		checkProcessFail(process);
		//Stdout.formatln("process finished");+/
	}
	
	if(compileArray.length)
	{
		if(!globalParams.useOP && !globalParams.useOQ)
		{
			void doGroup(Module[] group)
			{
				char[][] args;

				args ~= globalParams.compilerName;
				args ~= globalParams.compilerOptions;
				args ~= "-c";
				args ~= extraArgs;

				foreach(m; group)
					args ~= m.path;

				execute(args);

				if (moveObjects) {
					foreach(m; group)
						Path.rename(m.lastName ~ globalParams.objExt, m.objFile);
				}
			}

			int[char[]] lastNames;
			Module[][] passes;

			foreach(m; compileArray)
			{
				char[] lastName = Ascii.toLower(m.lastName.dup);
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
			char[][] args;
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
			
			execute(args);
			

			if (moveObjects) {
				if (!globalParams.useOQ) {
					foreach(m; compiled)
						Path.rename(m.objFileInFolder, m.objFile);
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
	
	profile!("finding modules to be compiled")({
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
	});
	
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
		
		profile!("compileAndTrackDeps")({
			version (MultiThreaded) {
				final int threads = globalParams.threadsToUse;
				Module[][] threadNow = new Module[][threads];
				Module[][] threadLater = new Module[][threads];

				foreach (th; mtFor(.threadPool, 0, threads)) {
					auto mods = compileNow[compileNow.length * th / threads .. compileNow.length * (th+1) / threads];
					Trace.formatln("Thread {}: compiling {} modules", th, mods.length);
					
					if (mods.length > 0) {
						compileAndTrackDeps(mods, modules, threadLater[th]);
					}
				}
				
				foreach (later; threadLater) {
					compileLater ~= later;
				}
			} else {
				compileAndTrackDeps(compileNow, modules, compileLater);
			}
		});
		
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
