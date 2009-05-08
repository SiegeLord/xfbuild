module xf.build.GlobalParams;

private {
	import tango.io.model.IFile;
}


struct GlobalParams {
	char[] compilerName;
	char[][] compilerOptions;
	char[] objPath = ".objs";
	char[] depsPath = ".deps";
	version(Windows) {
		char[] objExt = ".obj";
		char[] exeExt = ".exe";
	} else {
		char[] objExt = ".o";
		char[] exeExt = "";
	}
	char[] outputFile;
	char[] workingPath;
	char[][] ignore;
	bool verbose;
	bool printCommands;
	int numThreads = 4;
	bool depCompileUseMT = true;
	bool dmdUseOP = true;
	bool recompileOnUndefinedReference = true;
	bool storeStrongSymbols = true; // TODO
	bool oneAtATime = false;
	char pathSep = FileConst.PathSeparatorChar;
	int maxModulesToCompile = int.max;
}

GlobalParams globalParams;
