module xfbuild.GlobalParams;

private {
	version (MultiThreaded) {
		import xfbuild.MT : ThreadPoolT;
	}
	
	import tango.io.model.IFile;
}


struct GlobalParams {
	char[] compilerName;
	char[][] compilerOptions;
	char[] objPath = ".objs";
	char[] depsPath = ".deps";
	//char[] projectFile = "project.xfbuild";
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
	
	bool manageHeaders = false;
	char[][] noHeaders;
	
	bool verbose;
	bool printCommands;
	int numThreads = 4;
	bool depCompileUseMT = true;
	bool useOQ = false;
	bool useOP = true;
	bool recompileOnUndefinedReference = false;
	bool storeStrongSymbols = true; // TODO
	char pathSep = FileConst.PathSeparatorChar;
	int maxModulesToCompile = int.max;
	int threadsToUse = 1;
	bool nolink = false;
	bool removeRspOnFail = true;
	
	// it sometimes makes OPTLINK not crash... e.g. in Nucled
	bool reverseModuleOrder = false;
        bool moduleByModule = false;

	bool recursiveModuleScan = false;
	bool useDeps = true;

	version (MultiThreaded) {
		bool manageAffinity = true;
	} else {
		bool manageAffinity = false;
	}

	size_t linkerAffinityMask = size_t.max;
}


GlobalParams	globalParams;

version (MultiThreaded) {
	ThreadPoolT		threadPool;
}
