module xf.build.Compiler;

private {
	import xf.build.GlobalParams;
	import xf.build.Module;
	import xf.build.Process;
	import xf.build.Misc;

	import xf.utils.Profiler;

	import tango.io.device.FileMap;
	import tango.sys.Process;
	import tango.io.stream.Lines;
	import tango.text.Regex;
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


void compileAndTrackDeps(Module[] compileArray, ref Module[char[]] modules, ref Module[] compileMore)
{
	Module getModule(char[] name, char[] path, bool* newlyEncountered = null) {
		if (auto mp = name in modules) {
			return *mp;
		} else {
			auto mod = new Module;
			mod.name = name.dup;
			mod.path = path.dup;
			mod.timeModified = Path.modified(mod.path).ticks;
			modules[mod.name] = mod;
			compileMore ~= mod;
			return mod;
		}
	}
	
	foreach (mod; compileArray) {
		mod.deps = null;
	}
	
	final depsFileName = "project.deps";
	try {
		compile(["-deps="~depsFileName], compileArray, modules, (char[] line) {
			if(!isVerboseMsg(line) && TextUtil.trim(line).length)
				Stderr(line).newline;
		});
	} catch (ProcessExecutionException e) {
		throw new CompilerError(e.msg);
	}
	
	scope depsFile = new FileMap(depsFileName);
	scope(exit) {
		depsFile.close();
		Path.remove(depsFileName);
	}

	profile!("deps parsing")({
		foreach (line; new Lines!(char)(depsFile)) {
			auto arr = line.decomposeString(cast(char[])null, ` (`, null, `) : `, null, ` (`, null, `)`);
			if (arr !is null) {
				char[] modName = arr[0].dup;
				char[] modPath = arr[1].dup;
				
				if (!isIgnored(modName)) {
					assert (modPath.length > 0);
					Module m = getModule(modName, modPath);

					char[] depName = arr[2].dup;
					char[] depPath = arr[3].dup;
					
					if (depName != "object" && !isIgnored(depName)) {
						assert (depPath.length > 0);
						
						Module depMod = getModule(depName, depPath);
						//Stdout.formatln("Module {} depends on {}", m.name, depMod.name);
						m.addDep(depMod);
					}
				}
			}
		}
	});
	
	foreach (mod; compileArray) {
		mod.timeDep = mod.timeModified;
		mod.wasCompiled = true;
		mod.needRecompile = false;
	}
}



void compile(
		char[][] extraArgs,
		Module[] compileArray,
		ref Module[char[]] modules,
		void delegate(char[]) stdout
) {
	void execute(char[][] args) {
		scope process = new Process(true, args);
		.execute(process);
		foreach(line; new Lines!(char)(process.stdout)) {
			stdout(TextUtil.trim(line));
		}

		Stderr.copy(process.stderr).flush;
		checkProcessFail(process);
		//Stdout.formatln("process finished");
	}
	
	if(globalParams.oneAtATime)
	{
		foreach(m; compileArray.dup)
		{
			if(m.isHeader)
				continue;

			char[][] args;
			args ~= globalParams.compilerName;
			args ~= globalParams.compilerOptions;
			args ~= "-c";
			args ~= "-of" ~ m.objFile;
			args ~= m.path;
			args ~= extraArgs;
			
			execute(args);
		}
	}
	else if(!globalParams.dmdUseOP)
	{
		void doGroup(Module[] group)
		{
			char[][] args;
			args ~= globalParams.compilerName;
			args ~= globalParams.compilerOptions;
			args ~= "-c";
			args ~= extraArgs;

			foreach(m; group)
			{
				//if(m.wasCompiled)
				//	continue;
			
				args ~= m.path;
			}

			execute(args);
			
			foreach(m; group)
			{
				//if(m.wasCompiled)
				//	continue;
				
				Path.rename(m.lastName ~ globalParams.objExt, m.objFile);
			}
		}
		
		/+bool[Module] done;
		Module[][] passes = new Module[][1];

		foreach(a; compileArray)
		{
			if(cast(bool)(a in done))
				continue;
				
			size_t count = 0;
			
			auto lastName = a.lastName;
			
			foreach(b; compileArray)
			{
				if(a is b)
					continue;
					
				if(icompare(lastName, b.lastName) == 0)
				{
					++count;
					done[b] = true;
					
					if(passes.length <= count)
						passes.length = count + 1;
					
					passes[count] ~= b;
				}
			}
			
			passes[0] ~= a;
		}+/
		
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

		//foreach(pass; passes)
		//	Stdout(pass).newline;
		
		foreach(pass; passes)
		{
			if(!pass.length)
				continue;

			doGroup(pass);
		}
	}
	else if(compileArray.length)
	{
		char[][] args;
		args ~= globalParams.compilerName;
		args ~= globalParams.compilerOptions;
		args ~= "-c";
		args ~= "-op";
		args ~= extraArgs;

		foreach(m; compileArray)
			args ~= m.path;
			
		auto compiled = compileArray.dup;
		
		execute(args);
		
		foreach(m; compiled)
			Path.rename(m.objFileInFolder, m.objFile);
	}
}


import tango.util.container.HashSet;


void compile(ref Module[char[]] modules/+, ref Module[] moduleStack+/)
{
	/+if (globalParams.verbose) {
		Stdout.formatln("compile called with: {}", moduleStack);
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
	
	while (compileArray) {
		compileMore = null;
		
		Module[] compileNow = compileArray;
		Module[] compileLater = null;
		
		if (compileNow.length > globalParams.maxModulesToCompile) {
			compileNow = compileArray[0..globalParams.maxModulesToCompile];
			compileLater = compileArray[globalParams.maxModulesToCompile .. $];
		}
		
		profile!("compileAndTrackDeps")({
			compileAndTrackDeps(compileNow, modules, compileMore);
		});
		
		//Stdout.formatln("compileMore: {}", compileMore);
		compileArray = compileLater ~ compileMore;
	}
}
