@echo off

rem cmd.exe must be restarted with enabled delayed variable evaluation
rem this is done in the needDelayed label and passes an extra param to this script

if not "%1"=="__delayed__" goto needDelayed

rem ---- Defaults

set xf=..
set MultiThreading=off
set StackTracing=on
set DebugSymbols=on

rem ---- Option parsing

shift
:parseOpts
if "%1"=="" goto optsParsed
	if "%1"=="--xf" (
		set xf=%2
		rem echo set xf root directory to !xf!
		shift
		shift
	) else if "%1"=="--help" (
		goto help
	) else if "%1"=="--with" (
		set enableDisableState=on
		goto enableDisableFeature
	) else if "%1"=="--without" (
		set enableDisableState=off
		goto enableDisableFeature
	) else (
		echo Unrecognized parameter: %1
		echo.
		goto help
	)
	goto parseOpts

	:enableDisableFeature
		if "%2"=="MultiThreading" (
			set MultiThreading=!enableDisableState!
		) else if "%2"=="StackTracing" (
			set StackTracing=!enableDisableState!
		) else if "%2"=="DebugSymbols" (
			set DebugSymbols=!enableDisableState!
		) else (
			echo Unrecognized feature: %2
			goto help
		)
		shift
		shift
	goto parseOpts

rem ----

:optsParsed

rem ---- Check if the required xf modules exist in the specified path

for /F %%X in (modList.lst) do (
	set foo=%%X
	if ".."=="!foo:~0,2!" (
		set fname=!xf!!foo:~2!
		if not exist !fname! (
			echo Could not locate !fname!, make sure to specify the --xf option correctly
			goto end
		)
	)
)

rem ---- Print out the config

echo Compiling xfBuild with the following options:
echo     MultiThreading = !MultiThreading!
echo     StackTracing   = !StackTracing!
echo     DebugSymbols   = !DebugSymbols!

rem ---- Create the rsp file

echo -ofxfbuild.exe > build.bat.rsp
echo tango.lib >> build.bat.rsp

if !DebugSymbols!==on   echo -g >> build.bat.rsp
if !MultiThreading!==on echo -version=MultiThreaded   >> build.bat.rsp
if !StackTracing!==on   echo -version=TraceExceptions >> build.bat.rsp

set foo="shit"
for /F %%X in (modList.lst) do (
	set foo=%%X

	rem if the path begins with two dots, replace that with the specified xf path
	if ".."=="!foo:~0,2!" (
		echo !xf!!foo:~2! >> build.bat.rsp
	) else (
		echo !foo! >> build.bat.rsp
	)
)

rem Finally build xfbuild
dmd @build.bat.rsp
del build.bat.rsp

goto end

:needDelayed
cmd /V:ON /c%0 __delayed__ %*
goto end

:help
echo Usage: %0 [--help] [--xf /path/to/xf]
echo.
echo Builds xfbuild using the dmd compiler.
echo.
echo --xf                 path of the xf library
echo --without [feature]  compiles xfbuild without specific functionality
echo --with [feature]     compiles xfbuild with specific functionality
echo     Available features:
echo         StackTracing   [default=on]
echo         DebugSymbols   [default=on]
echo         MultiThreading [default=off]
echo.

:end
