module xf.build.Compiler;

private {
	import xf.build.GlobalParams;
	import xf.build.Module;
	import xf.build.Process;

	import tango.sys.Process;
	import tango.io.stream.Lines;
	import tango.text.Regex;
	import Ascii = tango.text.Ascii;

	// TODO: better logging
	import tango.io.Stdout;
}

private {
	Regex	importSemanticStartRegex;
	Regex	importSemanticEndRegex;
	Regex	moduleSemantic1Regex;
	Regex	verboseRegex;
}

static this() {
	importSemanticStartRegex = Regex(`^Import::semantic\('([a-zA-Z0-9._]+)'\)$`);
	importSemanticEndRegex = Regex(`^-Import::semantic\('([a-zA-Z0-9._]+)', '(.+)'\)$`);
	moduleSemantic1Regex = Regex(`^semantic\s+([a-zA-Z0-9._]+)$`);
	verboseRegex = Regex(`^parse|semantic|function|import|library|code.*`);
}



void compileAndTrackDeps(Module[] compileArray, ref Module[char[]] modules, ref Module[] compileMore)
{
	Module[] moduleDepStack;
	Module m() {
		return moduleDepStack[$-1];
	}
	
	
	Module getModule(char[] name) {
		if (auto mp = name in modules) {
			return *mp;
		} else {
			auto mod = new Module;
			mod.name = name;
			modules[mod.name] = mod;
			return mod;
		}
	}
	
	foreach (mod; compileArray) {
		mod.deps = null;
	}
	
	compile(["-v"], compileArray, modules, (char[] line) {
		if (moduleSemantic1Regex.test(line)) {
			moduleDepStack = [getModule(moduleSemantic1Regex[1].dup)];
		}
		
		else if (importSemanticStartRegex.test(line)) {
			char[] modName = importSemanticStartRegex[1].dup;
			
			if ("object" == modName) {
			} else if (isIgnored(modName)) {
				/+if (globalParams.verbose)		// omg spam :P
					Stdout.formatln(modName ~ " is ignored");+/
			} else {
				moduleDepStack ~= getModule(modName);
			}
		}
		
		else if (importSemanticEndRegex.test(line)) {
			char[] modName = importSemanticEndRegex[1].dup;
			char[] modPath = importSemanticEndRegex[2].dup;
			
			if (modName != "object" && !isIgnored(modName)) {
				assert (modPath.length > 0);
				moduleDepStack = moduleDepStack[0..$-1];

				//Stdout.formatln("file for module {} : {}", modName, modPath);
				
				Module depMod = getModule(modName);
				if (depMod.path is null) {	// newly encountered module
					depMod.path = modPath;
					if (!depMod.isHeader) {
						depMod.timeModified = Path.modified(depMod.path).ticks;
						compileMore ~= depMod;
					}
				} else assert (depMod.path.length > 0);
				//Stdout.formatln("Module {} depends on {}", m.name, depMod.name);
				m.deps ~= depMod;
			}
		}

		else if(!verboseRegex.test(line) && TextUtil.trim(line).length)
			Stderr(line).newline;
	});
	
	foreach (mod; compileArray) {
		mod.timeDep = mod.timeModified;
		mod.wasCompiled = true;
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
			stdout(line);
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


void compile(ref Module[char[]] modules, ref Module[] moduleStack)
{
	if (globalParams.verbose) {
		Stdout.formatln("compile called with: {}", moduleStack);
	}
	
	bool[Module][Module] revDeps;
	foreach (mname, m; modules) {
		foreach (d; m.deps) {
			revDeps[d][m] = true;
		}
	}
	
	auto toCompile = new HashSet!(Module);
	{
		Module[] checkDeps;
		
		foreach (mod; moduleStack) {
			toCompile.add(mod);
			checkDeps ~= mod;
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
	
	if (globalParams.verbose) {
		Stdout.formatln("Modules to be compiled: {}", toCompile.toArray);
	}
	
	Module[] compileMore;
	Module[] compileArray = toCompile.toArray;
	
	while (compileArray) {
		compileMore = null;
		compileAndTrackDeps(compileArray, modules, compileMore);
		//Stdout.formatln("compileMore: {}", compileMore);
		compileArray = compileMore;
	}
}
