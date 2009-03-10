module xf.leoBuild.GlobalParams;

private {
	import tango.io.model.IFile;
}


struct GlobalParams {
	char[] compilerName = "dmd0xf";
	char[][] compilerOptions;
	char[] objPath = ".objs";
	char[] objExt = ".obj";
	char[] exeExt = ".exe";
	char[] outputFile;
	char[] workingPath;
	char[][] ignore = ["tango"];
	bool verbose;
	bool printCommands;
	int numThreads = 4;
	bool depCompileUseMT = true;
	bool dmdUseOP = true;
	bool recompileOnUndefinedReference = true;
	bool storeStrongSymbols = true; // TODO
	bool oneAtATime = false;
	char pathSep = FileConst.PathSeparatorChar;
}

GlobalParams globalParams;
