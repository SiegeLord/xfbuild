module xfbuild.Linker;

private {
	import xfbuild.GlobalParams;
	import xfbuild.Module;
	import xfbuild.Process;
	import xfbuild.Misc;

	import tango.sys.Process;
	import tango.io.stream.Lines;
	import tango.stdc.ctype : isalnum;
	import tango.text.Util : contains;
	import Array=tango.core.Array;

	// TODO: better logging
	import tango.io.Stdout;
}

/+private {
	Regex linkerFileRegex;
}

static this() {
	//defend\terrain\Generator.obj(Generator)
	//linkerFileRegex = Regex(`([a-zA-Z0-9.:_\-\\/]+)\(.*\)`);
}+/

bool isValidObjFileName(const(char)[] f) {
	foreach (c; f) {
		if (!isalnum(c) && !(`.:_-\/`.contains(c))) {
			return false;
		}
	}
	
	return true;
}



bool link(ref Module[char[]] modules,const(char[])[] mainFiles=null)
{
	bool retryCompile;

	const(char)[][] args;
	args ~= globalParams.compilerName;
	args ~= globalParams.compilerOptions;
	foreach (k;mainFiles){
		foreach(m; modules)
		{
			if(m.path==k){
				if(! m.isHeader) args ~= m.objFile;
				break;
			}
		}
	}
	foreach(k,m; modules)
	{
		if(m.isHeader || Array.contains(mainFiles,m.path))
			continue;
	
		args ~= m.objFile;
	}
	
	args ~= "-of" ~ globalParams.outputFile;
	
	if (!globalParams.recompileOnUndefinedReference) {
		executeCompilerViaResponseFile(
			args[0],
			args[1..$],
			globalParams.linkerAffinityMask
		);
	} else {
		scope process = new Process(true, args);
		execute(process);
		
		const(char)[] currentFile = null;
		Module currentModule = null;
		
		version (Windows) {
			auto procOut = process.stdout;
		} else {
			auto procOut = process.stderr;
		}
		
		foreach (line; new Lines!(char)(procOut))
		{
			line = TextUtil.trim(line);
			if (line.length > 0) {
				Stdout.formatln("linker: '{}'", line);
			}
		
			try
			{
				auto arr = line.decomposeString(cast(char[])null, "(", null, ")");
				
				//if(linkerFileRegex.test(line))
				if (arr && isValidObjFileName(arr[1]))
				{
					//currentFile = linkerFileRegex[1];
					currentFile = arr[1];
					
					foreach(m; modules)
						if(m.objFile == currentFile)
							currentModule = m;
					
					if(!currentModule && globalParams.verbose)
					{
						Stdout.formatln("{} doesn't belong to any known module", currentFile);
						continue;
					}
					
					if(globalParams.verbose)
						Stdout.formatln("linker error in file {} (module {})", currentFile, currentModule);
				}
				else if(/*undefinedReferenceRegex.test(line)*/ line.startsWith("Error 42:") && globalParams.recompileOnUndefinedReference)
				{
					if(globalParams.verbose)
					{
						if(!currentFile || !currentModule)
						{
							Stdout.formatln("no file.. wtf?");
							//continue; // as i currently recompile every file anyway...
						}
					
						/*Stdout.formatln("undefined reference to {}, will try to recompile {}", undefinedReferenceRegex[1], currentModule);
						
						currentModule.needRecompile = true;
						retryCompile = true;*/
						
						Stdout.formatln("undefined reference, will try teh full recompile :F");
						
						foreach(m; modules) m.needRecompile = true;
						retryCompile = true;
						
						break;
					}
				}
			}
			catch(Exception e)
			{
				if(currentFile && currentModule)
				{
					Stdout.formatln("{}", e);
					Stdout.formatln("utf8 exception caught, assuming linker error in file {}", currentModule);
				
					// orly!
					foreach(m; modules) m.needRecompile = true;
					retryCompile = true;
					
					break;
				} else {
					throw e;
				}
			}
		}
		
		try
		{
			checkProcessFail(process);
		}
		catch(Exception e)
		{
			version (Windows) {
				// I don't know if Windows is affected too?
			} else {
				// DMD somehow puts some linker errors onto stdout :S
				Stderr.copy(process.stdout).flush;
			}

			if(retryCompile && globalParams.verbose)
				Stdout.formatln("ignoring linker error, will try to recompile");
			else if(!retryCompile)
				throw e; // rethrow exception since we're not going to retry what we did
		}
	}
	
	globalParams.recompileOnUndefinedReference = false; // avoid infinite loop
	
	return retryCompile;
}
