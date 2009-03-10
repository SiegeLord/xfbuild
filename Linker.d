module xf.leoBuild.Linker;

private {
	import xf.leoBuild.GlobalParams;
	import xf.leoBuild.Module;
	import xf.leoBuild.Process;

	import tango.sys.Process;
	import tango.io.stream.Lines;
	import tango.text.Regex;

	// TODO: better logging
	import tango.io.Stdout;
}

private {
	Regex linkerFileRegex;
}

static this() {
	//defend\terrain\Generator.obj(Generator)
	linkerFileRegex = Regex(`([a-zA-Z0-9.:_\-\\/]+)\(.*\)`);
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
			Stdout(line).newline;
		
			try
			{
				if(linkerFileRegex.test(line))
				{
					currentFile = linkerFileRegex[1];
					
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
				else if(/*undefinedReferenceRegex.test(line)*/ line.length >= " Error 42:".length && line[0 .. " Error 42:".length] == " Error 42:" && globalParams.recompileOnUndefinedReference)
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
