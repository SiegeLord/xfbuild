module xfbuild.GlobalParams;

private {
	version (MultiThreaded) {
		static import xfbuild.MT;
	}
	
	import tango.io.model.IFile;
}


struct GlobalParams {
	const(char)[] compilerName;
	const(char)[][] compilerOptions;
	const(char)[] objPath = ".objs";
	const(char)[] depsPath = ".deps";
	//const(char)[] projectFile = "project.xfbuild";
	version(Windows) {
		const(char)[] objExt = ".obj";
		const(char)[] exeExt = ".exe";
	} else {
		const(char)[] objExt = ".o";
		const(char)[] exeExt = "";
	}
	const(char)[] outputFile;
	const(char)[] workingPath;
	const(char)[][] ignore;
	
	bool manageHeaders = false;
	const(char)[][] noHeaders;
	
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


__gshared GlobalParams globalParams;

version (MultiThreaded) {
	__gshared xfbuild.MT.ThreadPoolT		threadPool;
}
