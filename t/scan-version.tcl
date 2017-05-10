set test 1
source src/main.tcl
foreach f [lsort -ascii [list {*}[glob -tail -dir exes *.EXE *.exe] qwe]] {
    puts "f=$f v=[scan_version exes $f]"
}
