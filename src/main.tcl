# This file is part of MOO2 Launcher.
#
# Copyright (C) 2017 by Alexey Svirchevsky.
#
# This program is free software distributed under the
# terms of the GNU General Public License version 2,
# see src/LAUNCHER.TXT for details.

proc ll {a} {
    append ::log "$a\n"
    puts "debug: $a"
}

proc start {} {
    package require Tk
    option add *tearOff 0
    package require msgcat 1.5
    namespace import ::msgcat::mc

    set ::log ""
    set ::package_version ""
    set ::package_dir ""
    set ::rad 0
    set ::lastrad 0
    set ::gpath_err 0
    set ::dpath_err 0
    set ::mklinks 1
    set ::need_inst 0
    switch $::tcl_platform(platform) {
        windows {
            set ::pad1 3
            set ::pad2 7
            set ::bb_pad 2
            set ::bb_fsz 10
            set ::bl_fsz 12
        }
        default {
            set ::pad1 5
            set ::pad2 10
            set ::bb_pad 2
            set ::bb_fsz 10
            set ::bl_fsz 12
        }
    }

    set ::gui_dosbox [enum_widgets .r.dosbox_form Dosbox \
        {
            label m-output
            help  m-output-help
            spath {dosbox sdl output}
            options {surface overlay opengl openglnb ddraw}
            default openglnb
            readonly 1
        } {
            label m-res
            help  m-res-help
            spath {dosbox aux resolution}
            options {
                "640x480"
                "1280x960"
                "1920x1440"
                "1280x960 (scaler 2x)"
                "1920x1440 (scaler 3x)"
                "full screen 4:3"
                "full screen hw"
            }
            default "1280x960 (scaler 2x)"
            suffix res
        } {
            label m-lock-mouse
            help  m-lock-mouse-help
            spath {dosbox sdl autolock}
            checkbox 1
            default 0
        } {
            label m-switches
            help  m-switches-help
            spath {dosbox aux switches}
            options {"" /skipintro}
            default /skipintro
        } {
            label m-network
            help  m-network-help
            spath {dosbox aux network}
            options {m-network-disabled m-network-client m-network-server}
            default m-network-disabled
            readonly 1
            suffix net
            update update_dosbox_net
        }
    ]

    set ::appdir [norm_path [file dirname [info script]] ..]
    set ::version [string map {"\r" "" "\n" ""} \
                       [read_file_maybe [app_path src VERSION] ?]]
    ttk::style configure Big.TButton \
        -font [list -size $::bb_fsz -weight bold] \
        -padding $::bb_pad
    ttk::style configure Big.TLabel \
        -font [list -size $::bl_fsz -weight bold]

    ::msgcat::mcload [app_path src msgs]
    set ::info_title [mc m-winf-def-title]
    set ::info_desc [mc m-winf-def-desc]
    load_settings
    wm title . [mc m-title]
    if {1 || $::tcl_platform(platform) ne "windows"} {
        image create photo app-icon -file [app_path src icon.gif]
        wm iconphoto . -default app-icon
    }
    image create photo banner -file [app_path src banner.gif]
    set ::max_text_width [expr {[image width banner] - 2 * ($::pad1 + $::pad2)}]
    set ::wl [list -wraplength $::max_text_width]
    wm resizable . false false
    create_gui
}

proc f8 {s} {
    return [encoding convertfrom utf-8 $s]
}

proc t8 {s} {
    return [encoding convertto utf-8 $s]
}

proc norm_path {args} {
    set j [file normalize [file join {*}$args]]
    if {$::tcl_platform(platform) eq "windows"} {
        return [string map {"/" "\\"} $j]
    }
    return $j
}

proc app_path {args} {
    return [norm_path $::appdir {*}$args]
}

proc abs_path {args} {
    return [norm_path [pwd] {*}$args]
}

proc load_settings {} {
    set ::system_dosbox ""
    set ::settings_file [app_path MOOL2.settings]
    set ::detected_targets {}
    if {$::tcl_platform(platform) eq "windows"} {
        package require registry
        foreach f {
            {C:\Program Files (x86)\DOSBox-0.74\DOSBox.exe}
            {C:\Program Files\DOSBox-0.74\DOSBox.exe}
        } {
            if {[file isfile $f]} {
                set ::system_dosbox $f
                break
            }
        }
        set dt {}
        foreach {tag bits path val} {
            Steam -64bit
                {HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 410980}
                InstallLocation
            GOG -32bit
                {HKEY_LOCAL_MACHINE\SOFTWARE\GOG.com\Games\1207661633}
                PATH
        } {
            if {![catch {set target_dir [registry $bits get $path $val]}]} {
                set dosbox "$target_dir\\DOSBox\\DOSBox.EXE"
                if {![file isfile $dosbox]} {
                    set dosbox $::system_dosbox
                }
                lappend dt [dict create \
                    moo2-dir $target_dir \
                    dosbox.exe $dosbox \
                    tag $tag \
                ]
            }
        }
    } else {
        # both unix and macos
        set dt {}
        set path [file join $::env(HOME) "GOG Games"]
        set moos {}
        catch {set moos [lsort -ascii \
                             [glob -dir $path "Master of Orion 2*"]]}
        foreach p $moos {
            if {[file isdirectory $p]} {
                lappend dt [dict create moo2-dir [abs_path $p data] \
                                dosbox.exe [abs_path $p dosbox dosbox]]
            }
        }
        catch {set ::system_dosbox [exec which dosbox]}
    }
    if {$dt ne ""} {
        lappend dt [dict create \
                        label m-l-custom \
                        moo2-dir "" \
                        dosbox.exe $::system_dosbox]
    }
    set ::detected_targets $dt
    set ::settings {}
    eval [f8 [read_file_maybe $::settings_file [dict create]]]
    foreach {path def var} {
        {targets} "" ""
        {current_target} "" ""
        {dosbox aux target_server} moo2.thedopefish.com ::var_target_server
        {dosbox aux listen_port} 213 ::var_listen_port
    } {
        if {![dict exists $::settings {*}$path]} {
            dict set ::settings {*}$path $def
        }
        if {$var ne ""} {
            set $var [dict get $::settings {*}$path]
        }
    }
}

proc save_settings {} {
    set f [open $::settings_file "wb"]
    puts $f [t8 [list set ::settings $::settings]]
    close $f
}

proc find_best_source {} {
    set ::package_dir ""
    set ::package_version ""
    if {[catch {
        set files [lsort -ascii [glob -dir [app_path] MOO2.1.*]]
    }]} { return }
    set bestv ""
    foreach f $files {
        if {[file isdirectory $f]} {
            set v [scan_version $f ORION150.EXE]
            if {$v ne ""} {
                if {[version_compare $bestv $v] < 0} {
                    set ::package_dir $f
                    set ::package_version $v
                    set bestv $v
                }
            }
        }
    }
}

proc safe_read {f off count} {
    set res ""
    catch {
        seek $f $off
        set res [read $f $count]
    }
    return $res
}

proc scan_version {path fname} {
    if {$path eq ""} return ""
    set pathname [norm_path $path $fname]
    # windows has case-insensitive open, but on unix opening ORION2.EXE won't
    # open on Orion2.exe, and at least some GOG versions use mixed case
    if {$::tcl_platform(platform) ne "windows" && ![file isfile $pathname]} {
        set ff {}
        catch {set ff [lsort -ascii [glob -tails -dir $path *.*]]}
        foreach f $ff {
            if {[string equal -nocase $fname $f]} {
                set pn [norm_path $path $f]
                if {[file isfile $pn]} {
                    set pathname $pn
                    break
                }
            }
        }
    }
    if {[catch {set f [open $pathname "rb"]}]} return ""
    set v "?"
    if {[catch { seek $f 0 end; set fsize [tell $f] }]} return ""
    set lang ""
    switch $fsize {
        2612010 {
            set v "1.31"
            switch [safe_read $f 0x962F4 1] {
                "\x0" { set lang .en }
                "\x1" { set lang .de }
                "\x2" { set lang .fr }
                default { set v ? }
            }
        }
        2612563 {
            set v "1.31"
            set lang .es/it
        }
        2644842 {
            # 1.40
            set v [safe_read $f 2063699 7]
        }
        default {
            if {$fsize <= 2612563} {
                # pre-1.31
                set bytes [safe_read $f 0 $fsize]
                set pos [string first "Version 1." $bytes]
                if {$pos > -1} {
                    incr pos 8
                    set end [string first \0 $bytes $pos]
                    if {$end > $pos} {
                        set v [string range $bytes $pos [expr $end - 1]]
                    }
                }
            } else {
                # 1.50.x
                set v [lindex [split [safe_read $f 2026445 1000] \0] 1]
            }
        }
    }
    close $f
    if {![string match "1.\[1-9\]*" $v]} {
        set v ?
        set lang ""
    }
    return $v$lang
}

proc version_compare {a b} {
    set al [split $a .b-]
    set bl [split $b .b-]
    set bi 0
    foreach av $al {
        if {$bi >= [llength $bl]} { return 0 }
        set bv [lindex $bl $bi]
        if {$av ne $bv} {
            if {[catch [set x [expr {$av < $bv}]]]} {
                return [string compare $av $bv]
            }
            return [expr $x ? -1 : 1]
        }
        incr bi
    }
    if {[llength $al] < [llength $bl]} { return -1 }
    return 0
}

proc read_file {f} {
    set handle [open $f "rb"]
    set data [read $handle]
    close $handle
    return $data
}

proc write_file {f d {mode w}} {
    set handle [open $f $mode]
    puts -nonewline $handle $d
    close $handle
}

proc quote_conf_string {str} {
    set bad_chars " \r\t\n\xff^\"=;"
    if {[string match "*\[$bad_chars\]*" $str]} {
        set out "\""
        foreach ch [split $str ""] {
            if {$ch eq "^" || $ch eq "\""} {
                append out "^$ch"
            } else {
                append out $ch
            }
        }
        append out "\""
    } else {
        set out $str
    }
    return $out
}

proc cmd_launch_moo2 {} {
    foreach w [dict get $::gui_dosbox wlist] {
        set spath [dict get $w spath]
        set vname [dict get $w var]
        dict set ::settings {*}$spath [set $vname]
    }
    dict set ::settings dosbox aux listen_port $::var_listen_port
    dict set ::settings dosbox aux target_server $::var_target_server

    set pars [dict get $::settings dosbox]
    # may remain in settings from previous version
    dict unset pars sdl windowresolution
    dict unset pars sdl fullresolution
    dict unset pars sdl fullscreen
    set res [dict get $pars aux resolution]
    switch -regexp $res {
        "scaler 2x" {
            dict set pars render scaler "normal2x forced"
        }
        "scaler 3x" {
            dict set pars render scaler "normal3x forced"
        }
        "full screen 4:3" {
            dict set pars sdl fullscreen true
            dict set pars sdl fullresolution \
                [winfo screenwidth .]x[winfo screenheight .]
        }
        "full screen hw" {
            dict set pars sdl fullscreen true
            dict set pars sdl fullresolution original
        }
        "original" {}
        default {
            if {![regexp "^(\[0-9\]+)x(\[0-9\]*)\$" $res - x y]} {
                foreach {x y} {640 480} {}
            }
            if {$x <= 0} { set x 640 }
            if {$y eq ""} { set y 0 }
            if {$x * 3 != $y * 4} { set y [expr {$x * 3 / 4}] }
            set res ${x}x$y
            dict set ::settings dosbox aux resolution $res
            dict set pars sdl windowresolution $res
            set ::.r.dosbox_form.res $res
        }
    }
    save_settings

    set dbc_body "# DO NOT EDIT!
#
# This dosbox configuration file is generated by MOO2 Launcher every time it
# starts the game, so all manual edits will be lost! If you want to modify
# DOSBox configuration edit 150/dosbox.conf instead.

"
    dict for {sec kv} $pars {
        if {$sec eq "aux"} { continue }
        append dbc_body "\n\[$sec\]\n"
        dict for {k v} $kv {
            append dbc_body "$k=$v\n"
        }
    }
    set autoexec_ipx ""
    set netcur [.r.dosbox_form.net current]
    if {$netcur == 1} {
        set autoexec_ipx "ipxnet connect $::var_target_server"
    } elseif {$netcur == 2} {
        set autoexec_ipx "ipxnet startserver $::var_listen_port"
    }
    set switches [dget $::settings {dosbox aux switches} ""]
    set c [dict get $::settings current_target]
    set d [dict get $::settings targets $c]
    set dbc_name [norm_path $c 150 dosbox-150.conf]
    append dbc_body "
\[autoexec\]
mount C \"$c\"
C:
$autoexec_ipx
ORION150.EXE $switches
"
    write_file $dbc_name $dbc_body

    set enable_cfg "# THIS FILE HAS BEEN GENERATED BY MOO2 LAUNCHER
#
# This file lists enabled mods. It is generated automatically by MOO2 Launcher
# every time it starts the game, so all manual edits are lost. If you are not
# using Launcher and want to play a non-standard mod, then edit enables below.
# For example to play ICE-M, add \"enable ICE-M;\" and delete other enables.

"
    foreach mod_id [dict get $::enable_gui enabled] {
        append enable_cfg "enable [quote_conf_string $mod_id];\n"
        ll "enable [quote_conf_string $mod_id]"
    }
    write_file [norm_path $c 150 ENABLE.CFG] $enable_cfg

    exec [lindex $d 0] -noconsole \
        -conf $dbc_name \
        -conf [norm_path $c 150 dosbox.conf] \
        &
}

# opens files and urls with the appropriate app
proc native_open {f} {
    switch $::tcl_platform(platform) {
        windows {
            if [string match "*ORION2.LOG" $f] {
                exec notepad $f &
            } else {
                exec {*}[auto_execok start] "" $f &
            }
        }
        unix {
            exec xdg-open $f &
        }
        default {
            # mac
            exec open $f &
        }
    }
}

proc cmd_select_target {} {
    set t [lindex $::detected_targets $::rad]
    set ::gpath [dict get $t moo2-dir]
    set ::dpath [dict get $t dosbox.exe]
    cmd_check_path gpath
    cmd_check_path dpath
}

proc cmd_check_path {v} {
    set ::${v}_bad 0
    set val [set ::${v}]
    set status ::${v}_status
    set label .r.$v.s
    set err ::${v}_err
    set $err ""
    if {$val eq ""} {
        $label configure -foreground black
        set $status [mc m-$v-none]
        set $err [mc m-inst-no-$v]
        return
    }
    if {$v eq "dpath"} {
        if {[file isfile $val]} {
            $label configure -foreground darkgreen
            set ::dpath_status "OK"
        } else {
            $label configure -foreground red
            set ::dpath_status [mc m-dpath-not-found]
            set ::dpath_err [mc m-inst-no-dpath]
        }
        return
    }
    # else gpath
    if {![file isdirectory $val]} {
        $label configure -foreground red
        set ::gpath_status [mc m-gpath-no-dir]
    } else {
        set ver [scan_version $val ORION150.EXE]
        if {$ver eq ""} {
            set ver [scan_version $val ORION2.EXE]
        }
        if {$ver eq ""} {
            $label configure -foreground red
            set ::gpath_status [mc m-gpath-no-moo2 ORION2.EXE ORION150.EXE]
        } elseif {$ver eq "?"} {
            $label configure -foreground red
            set ::gpath_status [mc m-gpath-ver?]
            set ::gpath_err [mc m-inst-unknown]
        } elseif {[version_compare $ver 1.31] < 0} {
            $label configure -foreground red
            set ::gpath_status [mc m-gpath-ver-old $ver]
            set ::gpath_err [mc m-inst-outdated $ver]
        } else {
            $label configure -foreground darkgreen
            set ::gpath_status [mc m-gpath-ver-ok $ver]
        }
    }
}

proc copy_recursive {from to {depth 0}} {
    if {![catch {set files [lsort -ascii [glob -tails -dir $from *]]}]} {
        foreach f $files {
            set pf [norm_path $from $f]
            set pt [norm_path $to $f]
            if {[file isdir $pf]} {
                if {[file exists $pt] && ![file isdir $pt]} { file delete $pt }
                if {![file exists $pt]} {file mkdir $pt}
                copy_recursive $pf $pt [expr $depth + 1]
            } else {
                # don't overwrite user files
                if {[file exists $pt]} {
                    if {$depth == 1 && $f eq "USER.CFG"} { continue }
                    if {$f eq "dosbox.conf"} { continue }
                    if [string match "BUILD*.CFG" $f] { continue }
                    if [string match "MAIN*.LUA" $f] { continue }
                }
                file copy -force $pf $pt
            }
        }
    }
}

proc quote_xdg_string {s} {
    # quote \ \n \r
    return [string map { \\ \\\\ "\n" \\n "\r" \\r } $s]
}

proc quote_xdg_exec_argument {s} {
    # quote \ " ` $ and surround with quotes
    set res [string map { \\ \\\\ \" \\\" \` \\` \$ \\\$ } $s]
    return "\"$res\""
}

proc create_shortcut {} {
    switch $::tcl_platform(platform) {
        windows {
            package require twapi
            set lnk [abs_path [::twapi::get_shell_folder desktopdirectory] \
                         "MOO2 $::package_version.lnk"]
            ::twapi::write_shortcut $lnk \
                -path [app_path "MOO2 Launcher.exe"] \
                -workdir [app_path]
        }
        default {
            # unix
            set script_path ""
            foreach c [split [app_path src main.tcl] "" ] {
                if {[regexp "\[\"'\\><~|&;\$*?#()` \t\n\]" $c]} {
                    append script_path "\\"
                }
                append script_path $c
            }
            set desktop [abs_path [exec xdg-user-dir DESKTOP] \
                             MOO2-1.50.desktop]
            set main [quote_xdg_exec_argument [app_path moo2-launcher]]
            set Exec [quote_xdg_string "tclsh $main"]
            set Icon [quote_xdg_string [app_path src icon.gif]]
            set Path [quote_xdg_string [app_path]]
            write_file $desktop "\[Desktop Entry\]
Encoding=UTF-8
Type=Application
Name=MOO2 $::package_version
GenericName=MOO2 $::package_version
Comment=MOO2 $::package_version
Exec=$Exec
Categories=Game;
Icon=$Icon
Path=$Path
"
            exec chmod +x $desktop
        }
    }
}

proc cmd_install {} {
    set err "";
    if {$::gpath_err ne ""} {
        set err $::gpath_err
    } elseif {$::dpath_err ne ""} {
        set err $::dpath_err
    } elseif {$::package_dir eq ""} {
        set err [mc m-inst-no-patch]
    }
    if {$err ne ""} {
        tk_messageBox -title [mc m-inst-err-title] -icon warning -message $err
        return
    }
    if {[catch {copy_recursive $::package_dir $::gpath} err]} {
        tk_messageBox -title [mc m-inst-err-title] -icon warning \
            -message [mc m-inst-copy-failed $err]
        return
    }
    if {$::mklinks} {
        if {[catch {create_shortcut} err]} {
            ll "failed to create shortcut: $err"
        }
    }
    dict set ::settings targets $::gpath [list $::dpath]
    dict set ::settings current_target $::gpath
    set ::need_inst 0
    save_settings
    tk_messageBox -title [mc m-inst-ok-title] \
        -message [mc m-inst-ok-ver-path $::package_version $::gpath]
    create_gui
}

proc cmd_create_gui_inst {} {
    set ::need_inst 1
    catch { destroy .i }
    create_gui
}

proc cmd_browse {v} {
    if {$v eq "gpath"} {
        set p [norm_path [tk_chooseDirectory -initialdir $::gpath]]
        if {$p ne ""} {
            set ::gpath $p
        }
    } else {
        set types {}
        if {$::tcl_platform(platform) eq "windows"} {
            set types {{"Windows executables" {.exe}}}
        }
        set p [norm_path [tk_getOpenFile -initialfile $::dpath -filetypes $types]]
        if {$p ne ""} {
            set ::dpath $p
        }
    }
    cmd_check_path $v
}

proc cmp_ord_name {a b} {
    if {[lindex $a 0] != [lindex $b 0]} {
        return [expr [lindex $a 0] - [lindex $b 0]]
    }
    return [string compare [lindex $a 1] [lindex $b 1]]
}

proc check_enables {mods enabled} {
    ll "checking enables: $enabled"
    # marking enabled mods
    foreach e $enabled {
        if {![dict exists $mods $e]} {
            error "Mod '$e' is enabled but can't be found in mods list."
        }
        set ec [dict get $mods $e conf mod_class]
        if {$ec ne ""} {
            dict for {m mdata} $mods {
                if {$ec eq [dict get $mdata conf mod_class]} {
                    dict set mods $m enabled 0
                }
            }
        }
        dict set mods $e enabled 1
    }
    dict for {m mdata} $mods {
        dict set mods $m broken 0
    }
    # check brokens among enabled
    dict for {m mdata} $mods {
        if {![dict get $mdata enabled]} { continue }
        if {[dict get $mdata broken]} {
            error "Enabled mod '$m' is marked as broken."
        }
    }
    set ord_cur -1
    while {1} {
        set best_ord ""
        set best_mods {}
        dict for {m mdata} $mods {
            set mo [dict get $mdata conf mod_order]
            if {$mo > $ord_cur && [dict get $mdata enabled]} {
                if {$best_ord eq "" || $mo <= $best_ord} {
                    if {$best_ord ne "" && $mo < $best_ord} {
                        set best_mods {}
                    }
                    set best_ord $mo
                    lappend best_mods $m
                }
            }
        }
        if {$best_mods eq {}} { break }
        set normal {}
        foreach m $best_mods {
            if {[dict get $mods $m conf mod_class] ne ""} {
                lappend normal $m
            }
        }
        if {[llength $normal] > 1} {
            error [mc m-mod-order-conflict-ord-mods $best_ord $normal]
        }
        set ord_cur $best_ord
    }
}

proc upset {var value} {
    if {$var ne ""} {
        upvar 2 $var x
        set x $value
    }
}

proc control_cur_mod {con {enabled ""} {shown ""} {mclass ""}} {
    set mlist [dict get $con mods]
    set var [dict get $con var]
    set widget [dict get $con widget]
    if {[llength $mlist] > 1} {
        set v [$widget current]
        set iscore [string match *.modpick0 $widget]
        if {!$iscore} { incr v -1 }
        if {$v >= 0} {
            upset $enabled [lindex $mlist $v]
            upset $shown [lindex $mlist $v]
        } else {
            upset $enabled ""
            upset $shown ""
        }
    } else {
        if {[set $var]} { upset $enabled [lindex $mlist 0] }
        upset $shown [lindex $mlist 0]
    }
    upset $mclass [dict get $con mclass]
}

proc update_enables {wi} {
    set e {}
    set i 0
    set controls [dict get $::enable_gui controls]
    if {[string match *.modpick0 $wi]} {
        set con0 [lindex $controls 0]
        set mod [lindex [dict get $con0 mods] [$wi current]]
        set e [list $mod {*}[dict get $::enable_gui mods $mod file_enable]]
        update_gui_by_enables $e
    } else {
        foreach con $controls {
            set en ""
            control_cur_mod $con en
            if {$en ne ""} { lappend e $en }
        }
    }
    if {$e ne [dict get $::enable_gui enabled]} {
        dict set ::enable_gui enabled $e
        catch { destroy .modf.enable_mods_label }
        if {[catch {check_enables [dict get $::enable_gui mods] $e} err]} {
            set ::enable_mods_label [f8 $err]
            grid [ttk::label .modf.enable_mods_label \
                      -textvariable ::enable_mods_label -foreground red] \
                -columnspan 2 {*}[padn $::pad1 1 0]
        }
    }
}

proc enum_widgets {fname flabel args} {
    set r 0
    set wlist {}
    foreach a $args {
        set d [dict create {*}$a]
        if {[dict exists $d skip]} { continue }
        if {![dict exists $d help]} {
            dict set d help "[dict get $d label]-help"
        }
        set suffix r$r
        if {[dict exists $d suffix]} { set suffix [dict get $d suffix] }
        dict set d cwidget $fname.$suffix
        dict set d lwidget $fname.label_$suffix
        dict set d var ::$fname.$suffix
        lappend wlist $d
        incr r
    }
    return [dict create fname $fname flabel $flabel wlist $wlist]
}

proc dget {d path {def ""}} {
    if {[dict exists $d {*}$path]} {
        return [dict get $d {*}$path]
    }
    return $def
}

proc sget+ {path {def ""}} {
    if {[llength $path] == 0} { return $def }
    if {![dict exists $::settings {*}$path]} {
        dict set ::settings {*}$path $def
    }
    return [dict get $::settings {*}$path]
}

proc mcm {key} {
    if {[string match "m-*" $key]} { return [mc $key] } else { return $key }
}

proc cmd_help {args} {
    if {[catch {cmd_help_aux {*}$args} err]} {
        ll "help update error: $err"
    }
}

proc cmd_help_aux {t args} {
    switch $t {
        dosbox {
            set i [lindex $args 0]
            set w [lindex [dict get $::gui_dosbox wlist] $i]
            if {[dict get $w help] ne ""} {
                set ::info_title [mc [dict get $w label]]
                set ::info_desc [mc [dget $w help ""]]
            }
        }
        modpick {
            set i [lindex $args 0]
            set con [lindex [dget $::enable_gui controls {}] $i]
            set mshown ""
            control_cur_mod $con "" mshown
            set mods [dict get $::enable_gui mods]
            if {$mshown ne ""} {
                set ::info_title [dict get $mods $mshown conf mod_name]
                set d [dget $mods [list $mshown conf mod_desc]]
                if {$d ne ""} {
                    set ::info_desc $d
                } else {
                    set ::info_desc [mc m-no-mod-desc]
                }
            }
        }
        mod {
            # TODO update info_ when mouse is over listbox
            # entry, probably impossible in Tk.
        }
        default {
            set ::info_title [mc $t]
            set ::info_desc [mc $t-desc]
        }
    }
}

proc hbind {widgets args} {
    foreach w $widgets {
        bind $w <Enter> $args
        bind $w <Button-3> cmd_toggle_info
    }
}

proc padn {n r c} {
    return [list -padx [expr {$c ? [list 0 $n] : $n}] \
                -pady [expr {$r ? [list 0 $n] : $n}]]
}

proc grid_pad_all {master padding} {
    foreach s [grid slaves $master] {
        set opts [dict create {*}[grid info $s]]
        set r [dict get $opts -row]
        set c [dict get $opts -column]
        set st [dict get $opts -sticky]
        if {$st eq {}} { set st ew }
        grid $s {*}[padn $padding $r $c] -sticky $st
    }
}

proc create_dosbox_frame {frame_info} {
    set fname [dict get $frame_info fname]
    set f [ttk::labelframe $fname -text [dict get $frame_info flabel]]
    set row 0
    foreach w [dict get $frame_info wlist] {
        set lwi [dict get $w lwidget]
        ttk::label $lwi -text [mc [dict get $w label]]
        set wi [dict get $w cwidget]
        set wvar [dict get $w var]
        set sval [sget+ [dict get $w spath] [mcm [dget $w {default} ""]]]
        set $wvar $sval
        set up [dget $w {update} ""]
        if {[dict exists $w options]} {
            # combobox
            set opts {}
            foreach o [dict get $w options] { lappend opts [mcm $o] }
            set rd {}
            if {[dict exists $w readonly]} { set rd {-state readonly} }
            ttk::combobox $wi -values $opts -textvariable $wvar {*}$rd
            if {$rd ne "" && [lsearch $opts $sval] == -1} { $wi current 0 }
            if {$up ne ""} { bind $wi <<ComboboxSelected>> $up }
        } elseif {[dict exists $w checkbox]} {
            # checkbox
            set cmd {}
            if {$up ne ""} { set cmd [list -command $up] }
            ttk::checkbutton $wi -variable $wvar {*}$cmd
            bind $wi <FocusIn> +[list focus .]
        } else {
            # entry
            ttk::entry $wi -textvariable $wvar
            set $wvar [sget+ [dict get $w spath] [dget $w {default} ""]]
        }
        hbind [list $lwi $wi] cmd_help dosbox $row
        incr row
        grid $lwi $wi
    }
    grid columnconfigure $fname 1 -weight 1
    grid_pad_all $f $::pad1
    return $f
}

proc update_dosbox_net {} {
    if {[winfo exists .r.dosbox_form]} {
        set cur [.r.dosbox_form.net current]
        set dbfl .r.dosbox_form.net_label
        set dbfe .r.dosbox_form.net_entry
        catch {
            destroy $dbfl
            destroy $dbfe
        }
        if {$cur != 0} {
            # client
            if {$cur == 1} {
                ttk::label $dbfl -text [mc m-connect-to]
                ttk::combobox $dbfe -textvariable ::var_target_server \
                              -values {moo2.thedopefish.com 127.0.0.1}
            # server
            } elseif {$cur == 2} {
                ttk::label $dbfl -text [mc m-udp-port]
                ttk::combobox $dbfe -textvariable ::var_listen_port \
                              -values {213 2213}
            }
            if $cur {
                hbind [list $dbfl $dbfe] cmd_help \
                    [expr {$cur == 1 ? "m-connect-to" : "m-udp-port"}]
                grid $dbfl $dbfe -sticky ew
                grid $dbfl -pady [list 0 $::pad1] -padx [list 15 $::pad1]
                grid $dbfe {*}[padn $::pad1 1 1]
            }
        }
    }
}

proc cmd_toggle_log {} {
    if {[winfo exists .log]} {
        destroy .log
        return
    }
    toplevel .log
    grid [ttk::label .log.text -textvariable ::log] \
        -sticky nw -row 0 -column 0
    grid columnconfigure .log.text 0 -weight 1
    grid rowconfigure .log.text 0 -weight 1
    wm geometry .log "=500x1000+400+300"
}

proc cmd_toggle_info {{reset 0}} {
    if {[winfo exists .r.i]} {
        destroy .r.i
        return
    }
    if {$reset} {
        set ::info_title [mc m-winf-def-title]
        set ::info_desc [mc m-winf-def-desc]
    }
    grid [ttk::frame .r.i] -sticky w
    grid [ttk::label .r.i.caption -textvariable ::info_title \
              -style Big.TLabel {*}$::wl] -sticky w
    grid [ttk::label .r.i.desc -textvariable ::info_desc {*}$::wl] -sticky w
    grid columnconfigure .r.i 0 -weight 1
    grid_pad_all .r.i $::pad2
    .r.i configure -height 125
    .r.i configure -width [winfo width .]
    grid propagate .r.i 0
}

# TODO: via create_frame
proc add_labeled_choice {controls_ frname ltext mlist choices mclass} {
    upvar $controls_ controls
    set row [llength $controls]
    set wi $frname.modpick$row
    set lwi $frname.mcl_$row
    ttk::label $lwi -text [f8 $ltext]
    set var ::var$wi
    set $var 0
    if {[llength $choices] > 0} {
        ttk::combobox $wi -state readonly -values [f8 $choices]
        $wi current 0
        bind $wi <<ComboboxSelected>> {update_enables %W}
    } else {
        set dis {}
        if {$row == 0} {
            set $var 1
            set dis {-state disabled}
        }
        ttk::checkbutton $wi -variable $var {*}$dis -command {update_enables %W}
        bind $wi <FocusIn> +[list focus .]
    }
    hbind [list $lwi $wi] cmd_help modpick $row
    grid $lwi $wi
    lappend controls [dict create \
                          widget $wi \
                          var $var \
                          mods $mlist \
                          mclass $mclass \
                         ]
}

proc create_mods_frame {ct conf_file} {
    set fn [create_mods_frame_aux $ct $conf_file]
    grid_pad_all $fn $::pad1
    return $fn
}

proc create_mods_frame_aux {ct conf_file} {
    set fn [ttk::labelframe .r.modf -text [mc m-frame-mods]]
    set row 0
    if {[catch {set gm [get_mods $ct [abs_path $ct $conf_file]]} err]} {
        # parse error
        grid [ttk::label $fn.err1 -text [mc m-conf-err] {*}$::wl]
        grid [ttk::label $fn.err2 -text $err -foreground red {*}$::wl]
        return $fn
    } elseif {[dget $gm mods ""] eq {}} {
        # no mods found
        grid [ttk::label $fn.no_mods -text [mc m-no-mods] {*}$::wl]
        return $fn
    }
    foreach w [dget $gm warns] { ll "get_mods warning: $w" }
    set mods [dict get $gm mods]

    # creating classes dicts
    set classes [dict create]
    dict for {m mod} $mods {
        set class [dict get $mod conf mod_class]
        set ord [dict get $mod conf mod_order]
        if {![dict exists $classes $class]} {
            dict set classes $class ord $ord
            dict set classes $class mods {}
        }
        set mlist [dict get $classes $class mods]
        lappend mlist $m
        dict set classes $class mods $mlist
        set ord [expr min($ord,[dict get $classes $class ord])]
        dict set classes $class ord $ord
    }

    # sorting classes by order
    set cseq {}
    dict for {c cl} $classes {
        set mlist [dict get $cl mods]
        dict set classes $c mods [lsort $mlist]
        lappend cseq [list [dict get $cl ord] $c]
    }
    set cseq [lsort -command cmp_ord_name $cseq]

    # placing widgets for mods with classes
    set controls {}
    foreach oc $cseq {
        set c [f8 [lindex $oc 1]]
        # skip classless and hidden mods
        if {$c eq "" || [string match "_*" $c]} { continue }
        set class [dict get $classes $c]
        set mlist [dict get $class mods]
        set choices {}
        if {[llength $mlist] > 1} {
            # <None> option is not added to core mods (zeroth control)
            if {$controls ne {}} {
                # choices are converted from utf8 just before widget creation
                set choices [list [t8 [mc m-mod-none]]]
            }
            foreach m $mlist {
                lappend choices [dict get $mods $m conf mod_name]
            }
        } else {
            set c [dict get $mods [lindex $mlist 0] conf mod_name]
        }
        set class_key "m-class-$c"
        set class_name [mc $class_key]
        if {$class_name eq $class_key} { set class_name $c }
        add_labeled_choice controls $fn [t8 $class_name] $mlist $choices $c
    }
    # placing classless mods widgets
    if {[dict exists $classes ""]} {
        set class [dict get $classes ""]
        set mlist [dict get $class mods]
        foreach m $mlist {
            set c [dict get $mods $m conf mod_name]
            add_labeled_choice controls $fn $c [list $m] {} ""
        }
    }

    set ::enable_gui [dict create \
        mods $mods \
        classes $classes \
        cseq $cseq \
        enabled {} \
        controls $controls \
    ]
    update_gui_by_enables [dict get $gm main_enable]

    grid columnconfigure $fn 1 -weight 1
    update_enables ""
    return $fn
}

proc reset_mod_control {con {mod_id ""}} {
    set mlist [dict get $con mods]
    set wi [dict get $con widget]
    if {[llength $mlist] > 1} {
        if {$mod_id eq ""} {
            $wi current 0
        } else {
            set cur [lsearch -exact $mlist $mod_id]
            if {$cur != -1} {
                if {![string match *.modpick0 $wi]} { incr cur }
                $wi current $cur
            }
        }
    } else {
        set var [dict get $con var]
        if {$mod_id eq ""} {
            set $var 0
        } elseif {[lindex $mlist 0] eq $mod_id} {
            set $var 1
        }
    }
}

proc update_gui_by_enables {en} {
    set en_good {}
    set mods [dict get $::enable_gui mods]
    set classes [dict get $::enable_gui classes]
    set controls [dict get $::enable_gui controls]
    foreach con $controls {
        set wi [dict get $con widget]
        if {[string match *.modpick0 $wi]} { continue }
        reset_mod_control $con ""
    }
    foreach e $en {
        if {![dict exists $mods $e]} { continue }
        foreach con $controls {
            if {[lsearch -exact [dict get $con mods] $e] != -1} {
                reset_mod_control $con $e
                lappend en_good $e
                break
            }
        }
    }
    return $en_good
}

proc bind_escapes w {
    bind $w <Button-1> [list destroy $w]
    bind $w <Button-3> [list destroy $w]
    bind $w <Escape> [list destroy $w]
}

proc cmd_about {} {
    catch {destroy .about}
    toplevel .about
    ttk::label .about.title -text [mc m-about-title $::version] \
        -justify center -style Big.TLabel
    ttk::label .about.text -text [mc m-about-text $::version] \
        -justify center
    grid .about.title -sticky ns -padx $::pad2 -pady {20 0}
    grid .about.text -sticky ns -padx $::pad2 -pady {15 20}
    grid rowconfigure .about all -weight 1
    wm resizable .about false false
    wm title .about [mc m-menu-about]
    bind_escapes .about
    tk::PlaceWindow .about widget .
}

proc cmd_dist_open {args} {
    native_open [norm_path $::package_dir {*}$args]
}

proc cmd_inst_open {args} {
    native_open [norm_path [dict get $::settings current_target] {*}$args]
}

proc make_path_frame {var} {
    set f [ttk::labelframe .r.$var -text [mc m-$var-label]]
    ttk::entry $f.e -textvariable "::$var"
    ttk::button $f.b -text [mc m-b-browse] -command [list cmd_browse $var]
    ttk::label $f.s -textvariable "::${var}_status" {*}$::wl
    grid $f.e $f.b
    grid $f.s -
    grid columnconfigure $f 0 -weight 1
    grid_pad_all $f $::pad1
    bind $f.e <Any-KeyRelease> [list cmd_check_path $var]
    return $f
}

proc make_inst_frame {} {
    set f [ttk::labelframe .r.if -text [mc m-select-moo2-inst]]
    set row 0
    foreach t $::detected_targets {
        set label [dict get $t moo2-dir]
        if {[dict exists $t label]} {
            set label [mc [dict get $t label]]
        }
        grid [ttk::radiobutton $f.$row -value $row -text $label \
                  -variable ::rad -command cmd_select_target]
        incr row
    }
    grid_pad_all $f $::pad1
    return $f
}

proc create_gui {} {
    destroy .r .m
    menu .m
    grid [ttk::frame .r] -sticky news
    grid [ttk::label .r.banner -image banner -background black]
    set ct [dict get $::settings current_target]
    set inst [expr {$::need_inst || $ct eq ""}]
    if {$inst} {
        find_best_source
        grid [ttk::label .r.inst_prompt \
                  -text [mc m-inst-prompt $::package_version] \
                  -style Big.TLabel {*}$::wl \
                  -justify center] -sticky n
        set ::gpath ""
        set ::dpath ""
        if {$::detected_targets eq {}} {
            grid [ttk::label .r.il -text [mc m-no-moo2-inst] {*}$::wl]
            set ::dpath $::system_dosbox
        } else {
            grid [make_inst_frame]
        }
        grid [make_path_frame gpath]
        grid [make_path_frame dpath]
        grid [ttk::checkbutton .r.links -text [mc m-mklinks] \
                  -variable ::mklinks] -sticky w
        grid [ttk::button .r.inst -text [mc m-b-install] \
                  -command cmd_install -style Big.TButton]
        if {$::detected_targets ne {}} {
            set i 0
            set found 0
            if {$ct ne ""} {
                foreach t $::detected_targets {
                    if {[dict get $t moo2-dir] eq $ct} {
                        set found $i
                        break
                    }
                    incr i
                }
            }
            .r.if.$found invoke
        }
        cmd_check_path dpath
        cmd_check_path gpath
    } else {
        set v [scan_version $ct ORION150.EXE]
        if {$v eq "" || $v eq "?"} {
            grid [ttk::label .r.inst_broken \
                      -text [mc m-run-broken [norm_path $ct ORION150.EXE]] \
                      {*}$::wl] -sticky n
        } else {
            grid [ttk::label .r.inst_prompt \
                      -text [mc m-run-prompt $v] \
                      -style Big.TLabel {*}$::wl \
                      -justify center] -sticky n
            grid [create_dosbox_frame $::gui_dosbox]
            grid [create_mods_frame $ct ORION2.CFG]
            grid [ttk::button .r.run -text [mc m-b-launch] \
                      -command cmd_launch_moo2 -style Big.TButton]
            hbind .r.run cmd_help m-b-launch-help
        }
        menu .m.actions
        .m.actions add command -label [mc m-menu-mods-dir] \
            -command {cmd_inst_open 150 mods}
        .m.actions add command -label [mc m-menu-game-dir] \
            -command {cmd_inst_open}
        .m.actions add command -label ORION2.LOG \
            -command {cmd_inst_open ORION2.LOG}
        .m.actions add command -label [mc m-menu-gui-log] \
            -command cmd_toggle_log
        .m.actions add separator
        .m.actions add command -label [mc m-b-reinstall] \
            -command cmd_create_gui_inst
        menu .m.show
        .m.show add command -label USER.CFG \
            -command {cmd_inst_open 150 USER.CFG}
        # show build*.cfg
        menu .m.show.build
        foreach m {"" 1 2 3 4 5 6 7 8 9 0} {
            .m.show.build add command -label "BUILD$m.CFG" \
                -command [list cmd_inst_open 150 build BUILD$m.CFG]
        }
        .m.show add cascade -menu .m.show.build -label [mc m-menu-build]
        # show main*.lua
        menu .m.show.main-lua
        foreach m {1 2 3 4 5 6 7 8 9 0} {
            .m.show.main-lua add command -label "MAIN$m.LUA" \
                -command [list cmd_inst_open 150 scripts main MAIN$m.LUA]
        }
        .m.show add cascade -menu .m.show.main-lua -label [mc m-menu-main-lua]
        .m add cascade -menu .m.show -label [mc m-menu-show]
        .m add cascade -menu .m.actions -label [mc m-menu-actions]
    }

    set cmd [expr {$inst ? "cmd_dist_open" : "cmd_inst_open"}]
    menu .m.help
    .m.help add command -label [mc m-menu-help-readme] \
        -command [list $cmd README_150.TXT]
    .m.help add command -label [mc m-menu-help-manual] \
        -command [list $cmd 150 docs MANUAL_150.PDF]
    .m.help add command -label [mc m-menu-help-add] \
        -command [list $cmd 150 docs MANUAL_150.XLS]
    .m.help add command -label "EXAMPLE.CFG" \
        -command [list $cmd 150 docs EXAMPLE.CFG]
    .m.help add separator
    .m.help add command -label [mc m-menu-irc] \
        -command {native_open http://webchat.quakenet.org/?channels=moo2}
    .m.help add command -label [mc m-menu-web] \
        -command {native_open http://www.moo2mod.com}
    .m.help add separator

    if {!$inst} {
        .m.help add command -label [mc m-menu-hints] \
            -command {cmd_toggle_info 1}
    }
    .m.help add command -label [mc m-menu-about] -command cmd_about
    .m add cascade -menu .m.help -label [mc m-menu-help]
    . configure -menu .m
    update_dosbox_net

    grid_pad_all .r $::pad2
    # the banner is special, there is no space between it and dialog
    grid .r.banner -padx 0 -pady [list 0 $::pad2]
}

proc read_file_maybe {f def} {
    if {[catch { set o [read_file $f] }]} {
        return $def
    } else {
        return $o
    }
}

proc expand_lang_pattern {lang pat} {
    set d [dict create \
        LANG {en de fr es it} \
        LANGUAGE {English German French Spanish Italian} \
        LANG_ID {0 1 2 3 4 5} \
    ]
    set out ""
    set par 0
    foreach s [split $pat "$"] {
        if {$par % 2} {
            if {$s eq ""} {
                append out $
            } elseif {[dict exists $d $s]} {
                append out [lindex [dict get $d $s] $lang]
            }
        } else {
            append out $s
        }
        incr par
    }
    return $out
}

proc parse_error {err} {
    upvar 1 ctx ctx
    upvar 1 fname path
    upvar 1 line line
    set out ""
    foreach p [dict get $ctx stack] {
        set out "${out}included from $p:\n"
    }
    if {$line > 0} {
        set out "${out}Error at $path:$line: "
    } else {
        set out "${out}"
    }
    dict set ctx error "$out$err"
    return -level 2 $ctx
}

proc bmatch {s bytes} {
    if {[string length $s] < [llength $bytes]} {
        return 0
    }
    binary scan $s c[llength $bytes] sbytes
    for {set i 0} {$i < [llength $bytes]} {incr i} {
        if {([lindex $sbytes $i] & 0xff) != [lindex $bytes $i]} {
            return 0
        }
    }
    return 1
}

# ctx
#   stack   -- list of caller configs
#   root    -- root directory to which all file names are relative
#   conf    -- config parameters parsed so far
#   lang    -- current language id
# fname     -- file name relative to root
# opt       -- if 1, the file is optional, so no error when doesn't exist
# enable    -- list of enables found
proc parse_conf {ctx fname opt} {
    set line 0
    foreach p [dict get $ctx stack] {
        if {$p eq $fname} {
            parse_error "File '$fname' includes itself"
        }
    }
    if {[catch { set body [read_file $fname] }]} {
        if {$opt} { return $ctx }
        parse_error "Unable to open file '$fname'"
    }
    if {[bmatch $body {0xff 0xfe}] || [bmatch $body {0xfe 0xff}]} {
        parse_error "UTF-16 is unsupported, convert '$fname' to UTF-8"
    }
    # stripping utf-8 mark if present
    if {[bmatch $body {0xef 0xbb 0xbf}]} {
        set body [string range $body 3 end]
    }
    incr line
    set conf {}
    set mode "search_key"
    set keys {}
    set vals {}
    set comment 0
    set quoted 0
    set escaped 0
    set token ""
    foreach c [split $body ""] {
        if {[string match "\[\r\n\]" $c]} {
            incr line
            if {$comment} {
                set comment 0
                continue
            }
        }
        if {$comment} { continue }
        if {$quoted} {
            if {$escaped} {
                set found 0
                foreach map {{t "\t"} {r "\r"} {n "\n"}} {
                    if {$c eq [lindex $map 0]} {
                        append token [lindex $map 1]
                        set found 1
                        break
                    }
                }
                if {!$found} { append token $c }
                set escaped 0
                continue
            }
            if {$c eq "^"} {
                set escaped 1
                continue
            }
            if {$c eq "\""} {
                set quoted 0
                set mode "search_val"
                lappend vals $token
                continue
            }
            append token $c
            continue
        }
        set next_mode $mode
        if {![string match "\[ \t\xff\r\n=#;\]" $c]} {
            if {$c eq "\""} {
                if {$mode ne "search_val"} {
                    parse_error "quotes can't appear in keys or unquoted values"
                }
                set quoted 1
                continue
            }
            if {$mode eq "search_key"} { set mode "read_key" }
            if {$mode eq "search_val"} { set mode "read_val" }
            append token $c
            continue
        }
        if {$mode eq "read_key"} {
            lappend keys $token
            if {$keys eq {"stop"}} { return $ctx }
            if {$keys eq "include" || $keys eq "enable"} {
                set next_mode "search_val"
            } else {
                set next_mode "search_key"
            }
        } elseif {$mode eq "read_val"} {
            if {!$quoted && $token eq "0"} { set token "" }
            lappend vals $token
            set next_mode "search_val"
        }
        if {$c eq "#"} {
            set comment 1
        } elseif {$c eq "="} {
            if {[regexp "^(read_val|search_val)$" $mode]} {
                parse_error "'=' found after a value, expected ';'"
            }
            set next_mode "search_val"
        }
        set token ""
        if {$c ne ";"} {
            set mode $next_mode
            continue
        }
        if {$c eq ";"} {
            if {[llength $keys] == 0} {
                parse_error "empty statement is not allowed"
            }
            set k [lindex $keys 0]
            if {$k eq "enable"} {
                if {[llength $vals] != 1} {
                    parse_error "enable requires exactly one argument"
                }
                dict lappend ctx file_enable [lindex $vals 0]
            } elseif {$k eq "include"} {
                if {[llength $vals] != 1} {
                    parse_error "include requires exactly one argument"
                }
                set fname2 [expand_lang_pattern [dict get $ctx lang] \
                                [lindex $vals 0]]
                set opt2 0
                if {[string range $fname2 0 0] eq "?"} {
                    set opt2 1
                    set fname2 [string range $fname2 1 end]
                }
                set fname2 [abs_path [dict get $ctx root] {*}[split $fname2 "\\/"]]
                set old_stack [dict get $ctx stack]
                dict lappend ctx stack $fname
                set ctx [parse_conf $ctx $fname2 $opt2]
                dict set ctx stack $old_stack
                if {[dict exists $ctx error]} { return $ctx }
            } elseif {[regexp "^(mod_.*|scan_mods|.*\.lbx)$" $k]} {
                if {[llength $keys] != 1} {
                    parse_error "parameter $k is not a table"
                }
                if {[llength $vals] != 1} {
                    parse_error "parameter $k requires exactly one value"
                }
                set v [lindex $vals 0]
                if {$k eq "mod_order"} {
                    if {[string match "0\[0123456789\]*" $v]} {
                        if {[regexp "^\[01\]+$" $v]} {
                            set res 0
                            foreach c [split $v ""] {
                                set res [expr $res * 2 + $c]
                            }
                            set v $res
                        } else {
                            parse_error [mc m-mod-order-bin $v]
                        }
                    } elseif {[string is integer $v]} {
                        set v [expr $v + 0]
                    } else {
                        parse_error "mod_order must be a valid integer, got '$v'"
                    }
                }
                dict set ctx conf $k $v
            }
            set keys {}
            set vals {}
            set mode "search_key"
            continue
        }
    }
    if {$mode ne "search_key" || [llength $keys]} {
        parse_error "unterminated statement at the end of file"
    }
    return $ctx
}

proc get_mods {root conf_file} {
    set lang [read_file_maybe [norm_path $root language.ini] 0]
    if {![string match "\[012345\]" $lang]} { set lang 0 }
    set ctx [parse_conf [dict create \
        root $root \
        stack {} \
        conf {} \
        lang $lang \
    ] $conf_file 0 ]
    if {[dict exists $ctx error]} {
        error [dict get $ctx error]
    }
    set mods [dict create]
    set warns {}
    set err ""
    if {[dict exists $ctx conf scan_mods]} {
        set scan_path [norm_path $root {*}[split [dict get $ctx conf scan_mods] "\\/"]]
        if {[catch {set ff [glob -join -dir $scan_path * *.CFG]} err]} {
            ll "scan failed: $err scan_path=$scan_path root=$root"
            return [dict create warns $err]
        }
        foreach f $ff {
            set f [norm_path $f]
            set ctxm [parse_conf [dict create \
                root $root \
                stack {} \
                conf {} \
                lang $lang \
            ] $f 0]
            if {[dict exists $ctxm error]} {
                lappend warns "Unable to load mod from $f: [dict get $ctxm error]"
                continue
            }
            if {![dict exists $ctxm conf mod_class]} {
                dict set ctxm conf mod_class ""
            }
            if {![dict exists $ctxm conf mod_order]} {
                dict set ctxm conf mod_order 1000
            }
            if {![dict exists $ctxm conf mod_id]} {
                lappend warns "Invalid mod file $f: no mod_id specified."
                continue
            }
            set id [dict get $ctxm conf mod_id]
            if {![dict exists $ctxm conf mod_name] \
                || [dict get $ctxm conf mod_name] eq ""} {
                dict set ctxm conf mod_name $id
            }
            set broken 0
            if {[dict exists $mods $id]} {
                lappend warns "Files $f and [dict get $ctxm file] both have mod_id=$id, ignoring both."
                dict set mods $id broken 1
                set broken 1
            }
            dict set mods $id [dict create \
                conf [dict get $ctxm conf] \
                file $f \
                broken $broken \
                enabled 0 \
                file_enable [dget $ctxm file_enable] \
            ]
        }
    }
    return [dict create mods $mods warns $warns \
                main_enable [dget $ctx file_enable]]
}

if {![info exists test]} { start }
