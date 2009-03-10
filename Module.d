module xf.build.Module;

private {
	import xf.build.GlobalParams;
	import xf.build.Misc;
	
	import TextUtil = tango.text.Util;
	import Path = tango.io.Path;
	import tango.io.device.File;
	import tango.io.stream.Lines;
	import tango.text.Regex;
	import tango.text.convert.Format;
	
	// TODO: better logging
	import tango.io.Stdout;
}


/+private {
	Regex moduleHeaderRegex;
}

static this() {
	moduleHeaderRegex = Regex(`module\s+([a-zA-Z0-9._]+)`);
}+/



class Module
{
	char[] name;
	char[] path;

	bool isHeader()
	{
		assert (path.length > 0, name);
		return path[$ - 1] == 'i';
	}

	char[] lastName()
	{
		auto dotPos = TextUtil.locatePrior(name, '.');
		if(dotPos == name.length) dotPos = 0;
		else ++dotPos;
		
		return name[dotPos .. $];
	}
	
	char[] objFileInFolder()
	{
		auto dotPos = TextUtil.locatePrior(path, '.');
		assert(dotPos != path.length);
		
		return path[0 .. dotPos] ~ globalParams.objExt;
	}
	
	char[][] depNames;
	Module[] deps;		// only direct deps
	
	long timeDep;
	long timeModified;
	
	bool wasCompiled;
	bool needRecompile;
	
	bool modified() { return timeModified > timeDep; }
	
	char[] toString() { return name; }
	
	private char[] objFile_;
	
	char[] objFile()
	{
		//if(dmdUseOP)
		//	return objFileInFolder;
	
		if(objFile_)
			return objFile_;
			
		return objFile_ =
			globalParams.objPath
			~ globalParams.pathSep
			~ TextUtil.replace(name.dup, '.', '-')
			~ globalParams.objExt;
	}
	
	hash_t toHash()
	{
		return typeid(typeof(path)).getHash(cast(void*)&path);
	}
	
	
	bool hasDep(Module mod) {
		foreach (d; deps) {
			if (d.name == mod.name) {
				return true;
			}
		}
		return false;
	}
	
	
	static Module fromFile(char[] path) {
		auto m = new Module;
		m.path = path;
		m.timeModified = Path.modified(m.path).ticks;

		auto file = new File(m.path);
		scope(exit) file.close();

		foreach(line; new Lines!(char)(file))
		{
			line = TextUtil.trim(line);
			
			//if(moduleHeaderRegex.test(line))
			if (auto arr = line.decomposeString(`module`, ` `, null, `;`))
			{
				//m.name = moduleHeaderRegex[1].dup;
				m.name = arr[0].dup;
				
				if(globalParams.verbose)
					Stdout.formatln("module name for file '{}': {}", path, m.name);
				
				break;
			}
		}

		if(!m.name)
			throw new Exception(Format("module '{}' needs module header", path));
			
		return m;
	}
}


bool isIgnored(char[] name)
{
	foreach(m; globalParams.ignore)
	{
		if(name.length >= m.length && name[0 .. m.length] == m)
			return true;
	}
	
	return false;
}
