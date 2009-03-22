module xf.build.Linker;

private {
	import xf.build.GlobalParams;
	import xf.build.Module;
	import xf.build.Process;
	import xf.build.Misc;

	import tango.sys.Process;
	import tango.io.stream.Lines;
	import tango.stdc.ctype : isalnum;
	import tango.text.Util : contains;

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

bool isValidObjFileName(char[] f) {
	foreach (c; f) {
		if (!isalnum(c) && !(`.:_-\/`.contains(c))) {
			return false;
		}
	}
	
	return true;
}



bool link(ref Module[char[]] modules)
{
	bool retryCompile;

	char[][] args;
	args ~= globalParams.compilerName;
	args ~= globalParams.compilerOptions;
	
	foreach(m; modules)
	{
		if(m.isHeader)
			continue;
	
		args ~= m.objFile;
	}
	
	args ~= "-of" ~ globalParams.outputFile;
	
	if(!globalParams.recompileOnUndefinedReference)
		executeAndCheckFail(args);
	else
	{
		scope process = new Process(true, args);
		execute(process);
		
		char[] currentFile = null;
		Module currentModule = null;
		
		foreach(line; new Lines!(char)(process.stdout))
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
		catch(Exception)
		{
			if(retryCompile && globalParams.verbose)
				Stdout.formatln("ignoring linker error, will try to recompile");
		}
	}
	
	globalParams.recompileOnUndefinedReference = false; // avoid infinite loop
	
	return retryCompile;
}
