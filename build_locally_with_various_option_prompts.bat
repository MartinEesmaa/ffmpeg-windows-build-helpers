@ECHO off
ECHO Welcome to this FFmpeg compile script.
ECHO This process will first install a local copy of Cygwin to a new directory "ffmpeg_local_builds".
ECHO Then it will prompt you for some options like 32 bit vs. 64 bit, free vs. non free dependencies.
ECHO It will then build the GCC cross compiler, followed by FFmpeg dependencies and FFmpeg itself.
ECHO There are also even *more* option available than what you'll be prompted for.
ECHO If you want more advanced options after the first pass, it will give instructions when done
ECHO on how to run it again with more advanced options.
ECHO.
ECHO Starting Cygwin install/update.
ECHO.
CD ffmpeg_local_builds
SETLOCAL ENABLEDELAYEDEXPANSION
IF NOT EXIST cygwin_local_install (
  MKDIR cygwin_local_install
  CD cygwin_local_install
  ECHO Downloading Cygwin setup executable.
  ECHO Keep an eye on this window for error warning messages from the Cygwin install. Some of them are expected.
  powershell -command "$clnt = new-object System.Net.WebClient; $clnt.DownloadFile(\"http://cygwinxp.cathedral-networks.org/cathedral/setup-x86-2.874.exe\", \"setup-x86-2.874.exe\")"
  START /wait setup-x86-2.874.exe ^
  -X ^
  --quiet-mode ^
  --no-admin ^
  --no-startmenu ^
  --no-shortcuts ^
  --no-desktop ^
  --site "http://cygwinxp.cathedral-networks.org/" ^
  --root !cd! ^
  --packages autoconf,autogen,automake,bison,cmake,cvs,ed,flex,gcc-core,gcc-g++,git,gperf,libtool,make,mercurial,ncurses,p7zip,patch,pax,pkg-config,subversion,texinfo,unzip,wget,yasm,zlib1g-dev
  REM wget for the initial script download as well as zeranoe's uses it
  REM ncurses for the "clear" command yikes!
  ECHO Done installing Cygwin.
  CD ..
) ELSE (
  ECHO Cygwin already installed.
)
ENDLOCAL
SET PATH=%cd%\cygwin_local_install\bin;%PATH%

ECHO.
SET /P "static=Would you like to build static FFmpeg binaries [Y/n]?"
ECHO.
IF /I "%static%"=="n" (
  bash.exe -c "./cross_compile_ffmpeg.sh --build-ffmpeg-static=n %2 %3 %4 %5 %6 %7 %8 %9"
) ELSE (
  bash.exe -c "./cross_compile_ffmpeg.sh %1 %2 %3 %4 %5 %6 %7 %8 %9"
)

ECHO.
ECHO Done with local build. Check output above to see if successfull.
ECHO If not successful, then you could try to rerun the script. It "should" pick up where it left off.
ECHO.
ECHO If you want more advanced configuration, then open '%cd%\cygwin_local_install\cygwin.bat' (which sets up the path for you). Then cd to '%cd%' and run the script manually yourself with -h, like:
ECHO $ cd /cygdrive/.../ffmpeg_local_builds
ECHO $ ./cross_compile_ffmpeg.sh -h
PAUSE
