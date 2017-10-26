REM
REM This batch file creates MOO2 Launcher.exe, a windows bootstrap executable
REM which contains tcl runtime. The actual code is sourced from src/main.tcl,
REM so this executable can not be used without files from src/.
REM

rmdir wrap.tmp /s /q
mkdir wrap.tmp
cd wrap.tmp
copy ..\src\win32.tcl MOOL2.tcl
..\misc\tclkitsh-8.5.9-win32.upx.exe ..\misc\sdx.kit qwrap MOOL2.tcl
..\misc\tclkitsh-8.5.9-win32.upx.exe ..\misc\sdx.kit unwrap MOOL2.kit
copy ..\misc\tclkit.ico MOOL2.vfs\
copy ..\misc\tclkit.inf MOOL2.vfs\
..\misc\tclkitsh-8.5.9-win32.upx.exe ..\misc\sdx.kit wrap MOOL2.exe -runtime ..\misc\tclkit-gui-8_6_6-twapi-4_1_27-x86-max.exe
del "..\MOO2 1.50 Launcher.exe"
move MOOL2.exe "..\MOO2 Launcher.exe"
cd ..
rmdir wrap.tmp /s /q
