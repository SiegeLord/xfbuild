module xfbuild.Process;

private {
	import xfbuild.GlobalParams;
	import Integer = tango.text.convert.Integer : toString;
	
	import tango.io.device.File;
	import tango.io.FilePath;
	import tango.text.Util;
	import tango.text.convert.Format;
	import tango.stdc.stringz;
	import tango.core.Thread;

	import tango.sys.Common;
	import tango.stdc.string;
	import tango.sys.Process;

	version (Windows) {
		extern (Windows) extern BOOL SetProcessAffinityMask(HANDLE, size_t);
		extern (Windows) extern BOOL GetProcessAffinityMask(HANDLE, size_t*, size_t*);
	}

	extern (C) extern int system(char*);
	
	// TODO: better logging
	import tango.io.Stdout;
}


class ProcessExecutionException : Exception {
	this (char[] msg) {
		super (msg);
	}
}


void checkProcessFail(Process process)
{
	auto result = process.wait();

	if(result.status != 0)
	{
		auto name = process.toString();
		
		if(name.length > 255)
			name = name[0 .. 255] ~ " [...]";
	
		throw new ProcessExecutionException(`"` ~ name ~ `" returned ` ~ Integer.toString(result.status));
	}
}

void execute(Process process)
{
	process.execute();
	
	if(globalParams.printCommands)
		Stdout(process).newline;
}


/**
 * 	Loosely based on tango.sys.Process with the following license:
	  copyright:   Copyright (c) 2006 Juan Jose Comellas. All rights reserved
	  license:     BSD style: $(LICENSE)
	  author:      Juan Jose Comellas <juanjo@comellas.com.ar>
*/
void executeAndCheckFail(char[][] cmd, size_t affinity)
{
	void runNoAffinity() {
		char[] sys = cmd.join(" ");
		char* csys = toStringz(sys);
		int ret = system(csys);
		
		if (ret != 0) {
			throw new ProcessExecutionException(`"` ~ sys ~ `" returned ` ~ Integer.toString(ret));
		}
	}
	
	version (Windows) {
		if (!globalParams.manageAffinity) {
			runNoAffinity();
		} else {
			final allCmd = cmd.join(" ");
			char* csys = toStringz(allCmd);

			STARTUPINFO startup;
			memset(&startup, '\0', STARTUPINFO.sizeof);
			startup.cb = STARTUPINFO.sizeof;
			startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
			startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
			startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
			
			PROCESS_INFORMATION info;
			memset(&info, '\0', PROCESS_INFORMATION.sizeof);
			
			if (CreateProcessA(
					null,		// lpApplicationName
					csys,
					null,		// lpProcessAttributes
					null,		// lpThreadAttributes
					true,		// bInheritHandles
					CREATE_SUSPENDED,
					null,		// lpEnvironment
					null,		// lpCurrentDirectory
					&startup,	// lpStartupInfo
					&info
			)) {
				if (!SetProcessAffinityMask(info.hProcess, affinity)) {
					throw new Exception(
						Format(
							"SetProcessAffinityMask({}) failed: {}",
							affinity,
							SysError.lastMsg
						)
					);
				}

				ResumeThread(info.hThread);				
				CloseHandle(info.hThread);

				DWORD rc;
				DWORD exitCode;

				// We clean up the process related data and set the _running
				// flag to false once we're done waiting for the process to
				// finish.
				scope (exit) {
					CloseHandle(info.hProcess);
				}

				rc = WaitForSingleObject(info.hProcess, INFINITE);
				if (rc == WAIT_OBJECT_0)
				{
					GetExitCodeProcess(info.hProcess, &exitCode);

					if (exitCode != 0) {
						throw new ProcessExecutionException(
							Format("'{}' returned {}.", allCmd, exitCode)
						);
					}
				}
				else if (rc == WAIT_FAILED)
				{
					throw new ProcessExecutionException(
						Format("'{}' failed with an unknown exit status.", allCmd)
					);
				}
			} else {
				throw new ProcessExecutionException(
					Format("Could not execute '{}'.", allCmd)
				);
			}
		}
	} else {
		// TODO: affinity

		runNoAffinity();
	}
}


void executeCompilerViaResponseFile(char[] compiler, char[][] args, size_t affinity) {
	char[] rspFile = Format("xfbuild.{:x}.rsp", cast(void*)Thread.getThis());
	char[] rspData = args.join("\n");
	/+if (globalParams.verbose) {
		Stdout.formatln("running the compiler with:\n{}", rspData);
	}+/
	File.set(rspFile, rspData);
	
	scope (failure) {
		if (globalParams.removeRspOnFail) {
			FilePath(rspFile).remove();
		}
	}
	
	scope (success) {
		FilePath(rspFile).remove();
	}
	
	executeAndCheckFail([compiler, "@"~rspFile], affinity);
}


size_t getNthAffinityMaskBit(size_t n) {
	version (Windows) {
		/*
		 * This basically asks the system for the affinity
		 * mask and uses the N-th set bit in it, where
		 * N == thread id % number of bits set in the mask.
		 *
		 * Could be rewritten with intrinsics, but only
		 * DMD seems to have these.
		 */
		
		size_t sysAffinity, thisAffinity;
		if (!GetProcessAffinityMask(
			GetCurrentProcess(),
			&thisAffinity,
			&sysAffinity
		) || 0 == sysAffinity) {
			throw new Exception("GetProcessAffinityMask failed");
		}

		size_t i = n;
		size_t affinityMask = 1;
		
		while (i-- != 0) {
			do {
				affinityMask <<= 1;
				if (0 == affinityMask) {
					affinityMask = 1;
				}
			} while (0 == (affinityMask & thisAffinity));
		}

		affinityMask &= thisAffinity;
		assert (affinityMask != 0);
	} else {
		// TODO

		assert (n < size_t.sizeof * 8);
		size_t affinityMask = 1;
		affinityMask <<= n;
	}

	return affinityMask;
}
