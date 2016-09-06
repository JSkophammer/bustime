# common.pl -- common variables + subroutines used by all submit scripts
#
#     Rush 102.42a9d Render Queue Software.		##RUSH_VERSION##
#     (C) Copyright 2009 Greg Ercolano. All rights reserved.
#
#     Submit scripts will load this file via:
#         use FindBin;
#         $G::progname = "some-name";
#         require "$FindBin::Bin/.common.pl";
#

###                  ##############################################
### GLOBAL VARIABLES ##############################################
###                  ##############################################

$G::iswindows  = ( defined($ENV{OS}) && $ENV{OS} eq "Windows_NT" ) ? 1 : 0;
$G::ismac      = ( -d "/Applications" ) ? 1 : 0;
$G::islinux    = ( -e "/proc/meminfo" ) ? 1 : 0;
$G::isirix     = ( -e "/etc/sys_id"   ) ? 1 : 0;
$G::devnull    = ( $G::iswindows ) ? "nul" : "/dev/null";
$G::pathsep    = ( $G::iswindows ) ? ";" : ":";			   # PATH separators
$ENV{RUSH_DIR} ||= ($G::iswindows ? "c:/rush" : "/usr/local/rush");# (set if unset)
$ENV{PATH}     = "$ENV{RUSH_DIR}/bin${G::pathsep}$ENV{PATH}";	   # rush/bin in path

$G::input = ( $G::ismac ) 
	       ? "$ENV{RUSH_DIR}/examples/bin/input.app/Contents/MacOS/input"
	       : "$ENV{RUSH_DIR}/examples/bin/input";
$G::input .= defined($ENV{RUSH_QCCHECK}) ? " -E" : "";		# quality control

# CUSTOMIZE AS NECESSARY
$ENV{SHELL}     = "/bin/sh";		# predictable system() behavior
$G::tmpdir      = ( $G::iswindows ) ? "c:/temp" : "/var/tmp";	# should be a local drive
$G::homedir     = ( $G::iswindows ) ? $G::tmpdir : $ENV{HOME};
$G::dotrushdir  = ( $G::iswindows ) ? "$G::tmpdir/.rush-$ENV{USERNAME}" : "$G::homedir/.rush";
$G::histfile    = "$G::dotrushdir/.$G::progname.hist";
$G::lastsubmit  = "$G::dotrushdir/.$G::progname-last";

if ( $G::iswindows && !defined($ENV{RUSH_TMPDIR}) ) 		# windows: prevents complaints from DOS
    { chdir($G::tmpdir); }					# about cwd being a UNC path

###                  ##############################################
### COMMON FUNCTIONS ##############################################
###                  ##############################################

# FIX COMMON PATH PROBLEMS
#    $1 - path to fix
#    Returns 'fixed' path.
#    Handles:
#        Backslashes -> Front slashes under windows
#        Convert to lowercase
#        Mapped drive letters -> UNC
#
sub FixPath($)
{
    my ($path) = @_;
    if ( $G::iswindows )
    {
	$path =~ s%\\%/%g;		# \path\file -> /path/file

	# ADD DRIVE MAP -> UNC CONVERSIONS HERE, IF ANY
	# $path =~ s%^x:%//sgi9/prod1%;		# x: -> //sgi9/prod1
	# $path =~ s%^y:%//sgi9/prod2%;		# y: -> //sgi9/prod2
	# $path =~ s%^z:%//sgi7/prod3%;		# z: -> //sgi7/prod3
    }
    else
    {
	# nuke automount stuff from path
	$path =~ s%^/tmp_mnt%%;
	$path =~ s%^/exports%%;
	$path =~ s%^/private/automount%%;	# Mac OSX/JAGUAR
	$path =~ s%^/private/var/automount%%;	# Mac OSX/PANTHER
    }

    $path =~ s%/\./%/%g;		# /foo/./bar -> /foo/bar
    return($path);
}

# TAKE THE SIGN OF A NUMBER
#    1,2,3   ->  1
#   -1,-2,-3 -> -1
#    0       ->  0
#
sub sgn($)
{
    return( $_[0] > 0 ? 1 : $_[0] < 0 ? -1 : 0 );
}

# RETURN CURRENT WORKING DIRECTORY
sub GetCwd()
{
    my $cwd;
    if ( $G::iswindows ) { $cwd = `cd`; }
    else { $cwd = `pwd`; }
    chomp($cwd);
    return(FixPath($cwd));
}

# CONVERT A RELATIVE PATH TO AN ABSOLUTE PATH
#    $1 - relative path.
#    Returns an absolute, 'Fixed' version of the path.
#
sub AbsolutePath($)
{
    my $s = FixPath($_[0]);

    # CHECK IF ABSOLUTE PATH SPECIFIED
    if ( $G::iswindows )
    {
        if ( $s !~ m%^/% && $s !~ m%^[A-Za-z]:% )
            { $s = GetCwd() . "/$s"; }
    }
    else
    {
        if ( $s !~ m%^/% )
            { $s = GetCwd() . "/$s"; }
    }
    return(FixPath($s));
}

# SUCCESS WINDOW
#    $1 - success message; can be multiple lines
#
sub SuccessWindow($)
{
    open(OKWIN, "|$G::input -nofork -pvF -");
    print OKWIN $_[0];
    close(OKWIN);
}

# WARNING WINDOW
#    $1 - warning message; can be multiple lines
#
sub WarningWindow($)
{
    open(ERROR, "|$G::input -nofork -pwF -");
    print ERROR $_[0];
    close(ERROR);
}

# ERROR WINDOW
#    $1 - error message; can be multiple lines
#
sub ErrorWindow($)
{
    if ( open(ERROR, "|$G::input -nofork -pfF -") )
    {
	print ERROR $_[0];
	close(ERROR);
    }
    else
    {
        print "exec($G::input) failed: $!\n";
        print STDERR $_[0];
    }
}

# DIALOG WINDOW (NO DECALS)
#    $1 - message (can be multiple lines)
#    $2 - window title
#
sub MessageWindow($$)
{
    open(ERROR, "|$G::input -t \"$_[1]\" -pFan - -nofork");
    print ERROR $_[0];
    close(ERROR);
}

# CONFIRM YES/NO WINDOW
#    $1 - message; can be multiple lines
#    Returns: $? will be 0 if 'yes', non-zero for no.
#
sub YesNoWindow($)
{
    open(ERROR, "|$G::input -nofork -pyF -");
    print ERROR $_[0];
    close(ERROR);
}

# CHOICE WINDOW
#    $1 -- message
#    $2 -- choice msg #1
#    $3 -- choice msg #2
#
#    Example: ChoiceWindow("Choose either 'A' or 'B'", "A", "B");
#    Choice #2 will be the 'default'.
#    Returns the "choice msg" that was chosen.
#
sub ChoiceWindow($$$)
{
    my ($msg,$a,$b) = @_;
    open(ERROR, "|$G::input -nofork -pwyFYN - \"$b\" \"$a\" -t \"Please choose..\"");
    print ERROR $msg;
    return(close(ERROR) ? $b : $a);
}

# RETURN CONTENTS OF FILE
#    $1 - filename to load
#    Returns contents of file as a string.
#    On error, string will have an error msg starting with "ERROR:".
#
sub CatFile($)
{
    my ($filename) = @_;
    unless ( open(FILE, "<$filename" ) )
        { return("ERROR: CatFile($filename): $!\n"); }
    my $s = "";
    while ( <FILE> )
        { $s .= $_; }
    close(FILE);
    return($s);
}

# CONVERT OLD (LEGACY) KEYS TO NEW
#    $1 - filename to modify
#    $2 - list of regexs to apply to file, eg "s/this/that/; s/foo/bar/;"
#    Returns -1 on error, $errmsg has reason.
#
sub ApplyRegexToFile($$$)
{
    my ($filename,$regexs,$errmsg) = @_;
    unless ( open(FDIN, "<$filename") )
    {
        $$errmsg = "$filename: $!";
        return(-1);
    }
    unless ( open(FDOUT, ">$filename.new") )
    {
        $$errmsg = "$filename.new: $!";
        close(FDIN);
        return(-1);
    }
    while ( <FDIN> )
    {
        eval $regexs;
        print FDOUT $_;
    }
    close(FDIN);
    close(FDOUT);
    unless ( rename("$filename.new", "$filename") )
    {
        $$errmsg = "rename('$filename.new','$filename'): $!";
        return(-1);
    }
    return(0);
}

# POSIX Functions mixing under windows
#
use POSIX;
sub RUSH_WIFEXITED($)
    { return($G::iswindows?(($_[0]&0xff)==0):POSIX::WIFEXITED($_[0])); }
sub RUSH_WIFSIGNALED($)
    { return($G::iswindows?(($_[0]&0xff)!=0):POSIX::WIFSIGNALED($_[0])); }
sub RUSH_WEXITSTATUS($)
    { return($G::iswindows?(($_[0]>>8)&0xff):POSIX::WEXITSTATUS($_[0])); }
sub RUSH_WTERMSIG($)
    { return($G::iswindows?0:POSIX::WTERMSIG($_[0])); }

# Run a command with system(), do error checking
#    Returns non-zero on error, error message contains reason.
#    $1 - command to run
#    $2 - returned error message
#
sub RunCommand($$)
{
    my ($command, $errmsg) = @_;
    my $exitcode = 0;
    my $cmd0 = $command; $cmd0 =~ s/ .*//;
    $$errmsg = undef;
    my $err = system($command);
    if ( $err == -1 )
    {
	$$errmsg = "$cmd0: $!";

	# HANDLE SPECIAL CASE: 
	#     Linux returns EPERM if command not found, and one or more 
	#     path elements the user has no permission to read. 
	#     'EPERM' is technically correct, but confusing to most users.
	#
	if ( $! =~ /permission denied/i || $! =~ /No such file or directory/i )
	    { $$errmsg = "$cmd0: Command not found. (Probably '$cmd0' is not in your PATH)"; }
	$exitcode = -1;
    }
    elsif ( RUSH_WIFEXITED($err) )
    {
	$exitcode = RUSH_WEXITSTATUS($err);
	$$errmsg = ($exitcode == 0) ? undef : "$cmd0 FAILED: EXITCODE=$exitcode";
    }
    elsif ( RUSH_WIFSIGNALED($err) )
    {
	$exitcode = 128 + RUSH_WTERMSIG($err);
	$$errmsg = "$cmd0: terminated by signal " . RUSH_WTERMSIG($err);
    }
    return($exitcode);
}

# RETURN LOG FILENAME FOR SPECIFIED FRAME IN CURRENT JOB
#    Assumes $ENV{RUSH_JOBID} is set to a valid jobid.
#
#    $1: frame number
#    Returns path to the log file for the specified frame.
#    Returns "-" if log could not be determined.
#
sub GetLogFile($)
{
    my ($frame) = @_;
    my $ljf = `rush -ljf $ENV{RUSH_JOBID}`;
    if ( $ljf =~ /LogDir: (\S+)/ )
    {
        my $logdir = $1;
        chomp($logdir);
        return("$logdir/$frame");
    }
    return("-");
}

# START IRUSH IN THE BACKGROUND
#    $1 - args for irush
#    NOTE: cwd is modified, to speed up irush starts
#
sub StartIrush($)
{
    my $args = $_[0];

    chdir($G::tmpdir);		# faster irush starts

    if ( $G::iswindows )
    {
        # Process::Create() ensures irush doesn't hang up parent input.exe
        #     ('eval' is needed to prevent unix from choking on 'use Win32')
        eval '
        use Win32::Process;
        my $pobj;
        my $cmd = "$ENV{RUSH_DIR}/bin/irush.exe";
        my $err = Win32::Process::Create($pobj, $cmd, "irush $args", 
                                         0, NORMAL_PRIORITY_CLASS, "$ENV{RUSH_DIR}");
        if ( $err == 0 )
        {
            my $errmsg = Win32::FormatMessage(Win32::GetLastError());
            $errmsg =~ s/\r//g;
            print(STDERR "Could not invoke irush: \'$cmd\': $errmsg");
            return(-1);
        }
        ';
    }
    else
    {
        my $cmd = "$ENV{RUSH_DIR}/bin/irush $args < $G::devnull > $G::devnull 2>&1";
        my $errmsg;
        if ( RunCommand($cmd, \$errmsg) )
            { print(STDERR "WARNING: $errmsg"); return(0); }
    }
    return(0);
}

# SUBMIT A JOB TO RUSH, SHOW CONFIRMATIONS, START IRUSH
#     Returns 0 if ok with $ENV{RUSH_JOBID} containing the jobid, or 1 on error.
#     $1 - submit host
#     $2 - text to submit
#     $3 - job title (can be "")
#     $4 - start irush (yes/no/ask)
#
sub RushSubmit($$$$)
{
    my ($submithost, $submit, $jobtitle, $startirush) = @_;
    if ( ! defined($startirush) ) { $startirush = "yes"; }	# backwards compat

    chdir($G::tmpdir);		# faster submit

# COMMENTED OUT -- IF 'COMMAND' GETS TOO LONG, USE SaveInput()/LoadInput() INSTEAD
#   # WRAP INDENTED LINES TO LINE ABOVE
#   #    eg. |command  foo bar \
#   #        |         zig zag
#   #
#   $submit =~ s/\n\s+//g;

    # CREATE TEMPORARY SUBMIT SCRIPT
    if ( CreateDotRushDir() < 0 ) { exit(1); }
    my $submitfile = "$G::dotrushdir/$G::progname-submit";
    unlink($submitfile);
    unless ( open(SUBMIT, ">$submitfile") )
	{ print STDERR "open($submitfile): $!\n"; exit(1); }
    print SUBMIT $submit;
    close(SUBMIT);

    # SUBMIT THE JOB
    my $out = "$G::dotrushdir/$G::progname-out";
    my $err = "$G::dotrushdir/$G::progname-err";
    unlink($out);
    unlink($err);

    my $cmd;
    if ( $G::iswindows ) 
    { 
        # WINDOWS: 'start /min' prevents flashing up DOS windows
        $cmd = "start /min /wait cmd /x /c " .
                "\"rush -submit $submithost < $submitfile 2> $err > $out\"";
    }
    else
    {
        $cmd = "rush -submit $submithost < $submitfile 2> $err > $out";
    }
    system($cmd);

    # CHECK FOR SUBMIT ERRORS
    #     With this system, the only real way to know it worked
    #     is to check the $out file for a line of RUSH_JOBID.
    #
    my $msg = CatFile($out) . CatFile($err);
    if ( -e $out )
    {
        # OUTPUT MESSAGE CONTAINS RUSH_JOBID? IT WORKED
        if ( $msg =~ /RUSH_JOBID.(\S+)/ ) 
        {
            # IT WORKED
            my $jobid = $ENV{RUSH_JOBID} = $1;
            my $inputcmd = ( $startirush eq "ask" ) 
               ? "$G::input -nofork -pvyFNY - \"No Irush\" \"Irush\""	# ask
               : "$G::input -nofork -pvF -";				# don't ask
            open(STARTIRUSH, "|$inputcmd");
            print STARTIRUSH "-----------------\n" .
                             "--- SUBMIT OK ---\n" .
                             "-----------------\n\n" .
                             $msg;
            unless ( close(STARTIRUSH) ) { return(0); }	# picked "No Irush"
            if ( $startirush eq "no" ) { return(0); }	# user doesn't want irush

            # INVOKE IRUSH
            my $irushargs = ( $jobtitle ne "" ) 
                ? "-title $jobtitle -button Frames $jobid"
                : "-button Frames $jobid";
            return((StartIrush($irushargs)!=0) ? 1 : 0);
        }
    }

    $msg = "*********************\n" .
           "*** SUBMIT FAILED ***\n" .
           "*********************\n\n" .
           "$msg";

    print STDERR "\n$msg";
    return(1);
}

# CHECK LOG FOR SPECIFIED ERROR MESSAGES
#    Open frame log, check for common error messages.
#        $1 - retry search string (if encountered, resets search)
#        $2..$n - error message search strings (regex's, etc)
#    Returns "" if no errors, or an error message.
#
sub LogCheck($@)
{
    my ($retrymsg, @searchmsgs) = @_;
    my $errmsg = "";
    unless ( open(LOG, "<$ENV{RUSH_LOGFILE}") )
    {
        print STDERR "LogCheck($ENV{RUSH_LOGFILE}): $! (skipping)\n";
        return(0);
    }
    while ( <LOG> )
    {
        # REMOVE LEADING/TRAILING VERTICAL WHITE
	#    Some renderers (vray) include extra \r's that can mess up searches. (GURU 01/07/2009)
	#
	$_ =~ s/^[\r\n]*//;		# remove leading vert white
	$_ =~ s/[\r\n]*$//;		# remove trailing vert white

        foreach my $search ( @searchmsgs )
        {
           if ( $_ =~ /$retrymsg/ ) { $errmsg = ""; }
           if ( $_ =~ /$search/ ) { $errmsg = $_; }
        }
    }
    close(LOG);
    return($errmsg);
}

# RETURN BASENAME OF A PATHNAME
#    $1 - pathname
#    Returns basename.
#
sub Basename($)
{
    $_[0] =~ s%.*[/\\]%%g;
    return($_[0]);
}

# PRE-MAIN
#    This code is executed when this file is sourced,
#    and is intended to be run before the script's MAIN.
#
{
    # PREVENT IRUSH SLOW STARTS UNDER WINDOWS
    if ( ! defined($ENV{HOME}) && $G::iswindows ) 
        { $ENV{HOME}=$G::homedir; }

    # GET ABSOLUTE PATH TO SELF
    #    Complain if path contains spaces.
    #
    $G::self = FixPath(AbsolutePath($0));

    # ABANDONED: LOOSES LEADING SLASH (UNC)
    #    if ( ! defined($FindBin::Bin) )
    #	{ $G::self = FixPath(AbsolutePath($0)); }		# old way (pre-102.42)
    #    else
    #	{ $G::self = FixPath($FindBin::Bin."/".Basename($0)); }

    if ( $G::self =~ / / )
    {
        ErrorWindow("Path to submit script contains spaces!\n\n".
                    "    Pathname is '$G::self'\n\n".
                    "Please move submit script to a directory\n".
                    "path that does not contain spaces.\n\n"); 
        exit(1);
    }

    # UNBUFFER STDOUT/STDERR, OPEN PERMS
    select(STDERR); $| = 1;
    select(STDOUT); $| = 1;
    umask(0);
}

# Let the user test the fixpath function
sub FixPathTest($)
{
    if ( CreateDotRushDir() < 0 ) { exit(1); }

    my $dbasefile = "$G::dotrushdir/.submit-testpath.in";
    my $lastfile  = "$G::dotrushdir/.submit-testpath.last";

    # Create 'last' file if none
    if (! -d $lastfile)
    {
        unless(open(TESTOUT,">$lastfile"))
            { ErrorWindow($lastfile); exit(1); }
        close(TESTOUT);
    }
    # Create screen
    unless(open(TESTOUT,">$dbasefile"))
        { ErrorWindow($dbasefile); exit(1); }
    print TESTOUT <<"EOF";
window
{
    name   "FixPath() Test"
    xysize 600 300
}
xy 200 25
box
{
    name      "FixPath() Test"
    labelsize 32
    align     0
    type      0
    labeltype 4
    labelfont 0
    xysize    600 30
    boxaround 0 0
}
xysize 400 80
inputmultiline "Filenames to test:" "Filenames" ""
button
{
    name          "Foo"
    color         132
    xysize        90 24
    updatecommand "perl $G::self -fixpath"
}
submit
{
    submitname      "Test"
    cancelname      "Cancel"
    submitcmd       "perl $G::self -fixpath "
    submitcolor     230
    cancelcolor     49
    cancelpushcolor 1
    showfail        1
    apphelp         on
}
EOF
    close(TESTOUT);
    unless ( exec("$G::input -d $dbasefile -f $lastfile") )
        { ErrorWindow("Can't exec($G::input): $!\n"); exit(1); }
}

# LOAD INPUT INFO FROM FILE
#    $1 - REFERENCE: '%in' hash 
#    $2 - filename containing key/value pairs entered by user
#    $3 - REFERENCE: returned error message, if any
#
#    Returns: 0 if OK
#            -1 on error, $errmsg has reason.
#
sub LoadInput($$$)
{
    my ($in, $filename, $errmsg) = @_;
    unless ( open(IN, "<$filename") )
        { $$errmsg = "LoadInput(${filename}): $!\n"; return(-1); }
    while ( <IN> )
    {
        if ( /^[\s+]*([^:]*): (.*)/ )
        {
            my ($key, $val) = ($1, $2);
            if ( defined($$in{$key}) )
                { $$in{$key} .= "\n$val"; }	# maintain white on subsequent lines
            else
            {
                $val =~ s/^\s+//;		# strip leading white
                $val =~ s/\s+$//;		# strip trailing white
                $$in{$key} = $val;
            }
        }
    }
    close(IN);
    return(0);
}

# CHANGE INPUT INFO
#    Returns -1 on error, $errmsg has reason.
#    Changes the value of a field in the named file.
#    Useful for forcing a field's value to a fixed value.
#
#    $1 - Filename of key/value input file to modify
#    $2 - Key name (eg. "DDRFrame")
#    $3 - New value (eg. "0")
#    $4 - Returned error message (if any)
#
sub ChangeInput($$$$)
{
    my ($filename, $keyname, $newvalue, $errmsg) = @_;
    unless ( open(FDIN, "<$filename") )
        { $$errmsg = "open() for reading: $filename: $!"; return(-1); }
    unless ( open(FDOUT, ">$filename.new") )
    {
        $$errmsg = "open() for writing: $filename.new: $!";
        close(FDIN);
        return(-1);
    }
    while ( <FDIN> )
    {
        s/(^[ \t]*)${keyname}: [^\n]*/$1${keyname}: ${newvalue}/g;
        print FDOUT $_;
    }
    close(FDIN);
    close(FDOUT);
    unless ( rename("$filename.new", "$filename") )
        { $$errmsg = "rename($filename.new,$filename): $!"; return(-1); }
    return(0);
}

# SAVE %IN TO FILENAME
#    $1 - REFERENCE: %in
#    $2 - filename to save to
#    $3 - REFERENCE: errmsg returned
#
#    Keyword order is not preserved.
#    Returns: 0 if OK
#            -1 on error, errmsg has reason.
#
sub SaveInput($$$)
{
    my ($in, $filename, $errmsg) = @_;
    unless ( open(OUT, ">$filename") )
        { print STDERR "ERROR: SaveInput(${filename}): $!\n"; return(-1); }
    foreach my $key ( sort ( keys ( %{$in} ) ) )
    {
        my $val = $$in{$key};
        if ( $val =~ /\n/ )
        {
            # MULTILINE DATA? PRECEDE EACH LINE WITH "Key:"
            foreach my $line ( split(/\n/, $val) )
                { printf(OUT "%16s: %s\n", $key, $line); }
        }
        else
            { printf(OUT "%16s: %s\n", $key, $val); }
    }
    close(OUT);
    return(0);
}

# SAVE USER'S SUBMIT FORM DATA TO A FILE FOR RENDERS TO ACCESS
#     Returns filename of actual data file.
#
sub SaveSubmitInfo($$)
{
    my ($in, $sidir) = @_;

    # MAKE SURE DIRECTORY EXISTS
    if ( ! -d $sidir )
    {
        unless ( mkdir($sidir, 0777) )
        {
            print STDERR "mkdir($sidir): $!\n" .
                         "Can't create log directory for submitinfo.in file.\n";
            exit(1);
        }
        # WINDOWS: OPEN ACLS FOR THE LOG DIRECTORY
        if ( $G::iswindows )
        {
            my $dirname = $sidir; $dirname =~ s%/%\\%g;
            system("cacls $dirname /e /c /g everyone:f");
        }
    }

    # SAVE TO FILE
    my $errmsg;
    my $sifile = "$sidir/submitinfo.in";
    if ( SaveInput($in, $sifile, \$errmsg) < 0 )
        { print "$errmsg\n"; exit(1); }

    return($sifile);
}

# RETURN ONE SUBMIT HOST, IF SEVERAL ARE SPECIFIED
#    Handles randomly picking one of the hosts.
#
sub PickOneSubmitHost($)
{
    my $host = $_[0];
    if ( $host eq "" )
        { return(""); }
    $host =~ s/^[\s+,]*//;	# remove leading white/commas
    $host =~ s/[\s+,]*$//;	# remove trailing white/commas
    my @hostlist = split(/[\s+,][\s+,]*/, $host);
    # Randomize if several hosts specified
    return( $hostlist[ time() % ( $#hostlist + 1 ) ] );
}

# PARSE STANDARD SUBMIT VARIABLES
#
#     $1 - REFERENCE: \%in already loaded from user
#     Returns $submit output.
#
#     Requirements:
#         LogFlags, AutoDump, ImageCommand, MaxTime, MaxTimeState
#         DoneMail, DumpMail, LogDirectory, Cpus, NeverUseCpus, 
#         SubmitOptions. SubmitHost, Job{StartDoneDump}Command
#
sub ParseStandardSubmit($)
{
    my ($in) = @_;
    my $submit = "";

    # IMAGE COMMAND
    if ( defined($$in{ImageCommand}) && $$in{ImageCommand} ne "" )
    {
        # SOMETHING SET? USE IT
        $submit .= "imgcommand      $$in{ImageCommand}\n";
    }
    else
    {
        # NOTHING SET? DEFAULT: INVOKE SELF WITH -imgcommand %04d
        $submit .= "imgcommand      ".
                    ( $G::iswindows ? "start /b wperl " : "perl ") .
                    "$G::self -imgcommand %04d\n";
    }

    # LOGFLAGS
    if ( defined($$in{LogFlags}) )
    {
        if ( $$in{LogFlags} eq "Keep Last" )
            { $submit .= "logflags        keeplast\n"; }
        if ( $$in{LogFlags} eq "Keep All" )
            { $submit .= "logflags        keepall\n"; }
    }

    # AUTODUMP
    if ( defined($$in{AutoDump}) &&
         ( $$in{AutoDump} ne "" && $$in{AutoDump} ne "-" ) )
        { $submit .= "autodump        $$in{AutoDump}\n"; }

    # MAXTIME/STATE
    if ( defined($$in{MaxTime}) &&
         ( $$in{MaxTime} ne "" && $$in{MaxTime} ne "-" ) )
        { $submit .= "maxtime         $$in{MaxTime}\n"; }

    if ( defined($$in{MaxTimeState}) &&
         ( $$in{MaxTimeState} ne "" && $$in{MaxTimeState} ne "-" ) )
        { $submit .= "maxtimestate    $$in{MaxTimeState}\n"; }

    $$in{Ram} ||= "1";
    if ( defined($$in{Ram}) &&
         ( $$in{Ram} ne "" && $$in{Ram} ne "-" ) )
        { $submit .= "ram             $$in{Ram}\n"; }

    # DONEMAIL/DUMPMAIL
    if ( defined($$in{DoneMail}) &&
         ( $$in{DoneMail} ne "" && $$in{DoneMail} ne "-" ) )
        { $submit .= "donemail        $$in{DoneMail}\n"; }

    if ( defined($$in{DumpMail}) &&
         ( $$in{DumpMail} ne "" && $$in{DumpMail} ne "-" ) )
        { $submit .= "dumpmail        $$in{DumpMail}\n"; }

    # WAITFOR
    if ( defined($$in{WaitFor}) && 
         ( $$in{WaitFor} ne "" && $$in{WaitFor} ne "-" ) )
        { $submit .= "waitfor         $$in{WaitFor}\n"; }

    # WAITFORSTATE
    if ( defined($$in{WaitForState}) && 
         ( $$in{WaitForState} ne "" && $$in{WaitForState} ne "-" ) )
        { $submit .= "waitforstate    $$in{WaitForState}\n"; }

    # MAX LOG SIZE SANITY
    if ( defined($$in{MaxLogSize}) &&
         ( $$in{MaxLogSize} eq "" || 
           $$in{MaxLogSize} eq "-" ||
           $$in{MaxLogSize} <= 0 ) )
        { $$in{MaxLogSize} = 0; }

    # RETRIES
    if ( defined($$in{Retries}) &&
         ( $$in{Retries} eq "" || $$in{Retries} eq "-" ) )
        { $$in{Retries} = 0; }

    # RETRY BEHAVIOR
    if ( defined($$in{RetryBehavior}) &&
         ( $$in{RetryBehavior} eq "" || $$in{RetryBehavior} eq "-" ) )
        { $$in{RetryBehavior} = "Fail"; }

    # SUBMIT HOST
    if ( defined($$in{SubmitHost}) &&
         ( $$in{SubmitHost} eq "" || $$in{SubmitHost} eq "-" ) )
        { $$in{SubmitHost} = ""; }

    # MULTILINE INPUT FIELDS
    foreach ( split(/\n/, $$in{Cpus}) )
        { $submit .= "cpus            $_\n"; }
    foreach ( split(/\n/, $$in{NeverUseCpus}) )
        { $submit .= "nevercpus       $_\n"; }
    foreach ( split(/\n/, $$in{SubmitOptions}) )
        { $submit .= "$_\n"; }

    # COMMON SENSE SANITY CHECKS
    if ( defined($$in{Frames}) && $$in{Frames} eq "" )
        { print STDERR ("Frames must be specified"); exit(1); }
    if ( defined($$in{Cpus}) && $$in{Cpus} eq "" ) 
        { print STDERR ("Cpus must be specified"); exit(1); }

    # JOB START/DONE/DUMP COMMAND
    if ( defined($$in{JobStartCommand}) )
        { $submit .= "jobstartcommand $$in{JobStartCommand}\n"; }
    if ( defined($$in{JobDoneCommand}) )
        { $submit .= "jobdonecommand  $$in{JobDoneCommand}\n"; }
    if ( defined($$in{JobDumpCommand}) )
        { $submit .= "jobdumpcommand  $$in{JobDumpCommand}\n"; }

    return($submit);
}

# HANDLE COMPUTING BATCHFRAMES FOR SUBMIT
#     $1 - REFERENCE: input \%in of already loaded user input
# Returns: ($batchframes, $batchend, $newframespec)
# Requires: Frames, BatchFrames, BatchClip
#
sub BatchFramesSubmit($)
{
    my ($in) = @_;

    $$in{BatchFrames} ||= "1";	# ensure batch set to /something/

    my $batchend = 0;
    my $batchframes = $$in{BatchFrames};
    my $newframespec = $$in{Frames};
    $batchframes = ( $batchframes eq "" || $batchframes eq "-" || $batchframes < 1 ) 
                        ? 1 : ($batchframes + 0);

    if ( $newframespec =~ /^([+-]*\d+)-([+-]*\d+)$/ )	# RANGE? ADJUST FOR BATCHING
    {
        my ($sfrm, $efrm) = ($1, $2);
        if ( $sfrm <= $efrm )
        {
            # NORMAL FORWARD FRAME RANGE? (1-100)
            $newframespec .= ",$batchframes";	# 1-100 -> 1-100,10
            if ( $$in{BatchClip} eq "yes" && $batchframes > 1 ) { $batchend = $2; }
        }
        else						# inverted frame range?
        {
            # INVERTED FRAME RANGE? (100-1)
            if ( $batchframes > 1 ) { $sfrm -= ($batchframes-1); }	# ie. batch=5, frames=100-1, result: 96-1,-5
            $newframespec = "$sfrm-$efrm,-$batchframes";

            # See if we can reach the end frame using batch value supplied.
            # If not, tack on an extra frame for that last bit, and set the batchclip.
            for ( my $x=$sfrm; $x>$efrm; $x -= $batchframes ) { }
            if ( $x < $efrm )
            {
                # Handle leftovers..
                $newframespec .= " $efrm";		# tack on the end frame separately
                if ( $$in{BatchClip} eq "yes" && $batchframes > 1 )
                {
                    $batchend = ($x+$batchframes-1);	# add a cap for that last frame so we don't re-render anything
                }
            }
        }
    }
    elsif ( $newframespec =~ /^([+-]*\d+)$/ )	# NO RANGE? DISABLE BATCHING
        { $batchframes = 1; }
    else
    {
        if ( $batchframes > 1 )			# BATCH NON-TRIVIAL RANGE?
        {
            print STDERR "\n*** BATCH FRAMES ERROR ***\n".
                         "When batching frames, you can only specify ".
                         "simple frame ranges like '1-100'. \n".
                         "Please change your 'Frames' setting.\n";
            exit(1);
        }
    }
    return($batchframes, $batchend, $newframespec);
}

# HANDLE COMPUTING BATCHFRAMES FOR RENDER
#     $1 - frame, eg. $ENV{RUSH_FRAME}
#     $2 - batch frames, eg. $opt{BatchFrames}
#     $3 - batch end, eg. $opt{BatchEnd}
#     Returns: ($sfrm, $efrm)
#
sub BatchFramesRender($$$)
{
    my ($frame, $batchfrms, $batchend) = @_;
    my $sfrm = $frame;
    my $efrm = ( $batchfrms < 2 ) ? $frame : ( $frame + $batchfrms - 1 );

    # BATCH FRAME TRUNCATION
    #    Avoid rendering leftover frames at end of a batch
    #
    if ( $batchfrms > 1 && $batchend > 0 && 
	 ( $sfrm <= $batchend && $efrm >= $batchend ) )
	{ $efrm = $batchend; }
    return($sfrm, $efrm);
}

### BATCH STEP VERSIONS OF THE ABOVE
###     These functions allow for a step rate to be specified,
###     in addition to a batch range.
###

# HANDLE COMPUTING BATCHFRAMES FOR SUBMIT (WITH STEP FRAMES)
#     $1 - REFERENCE: input \%in of already loaded user input
#     $2 - REFERENCE: new range frame specification
#
#  Returns: 0 if ok, -1 on error ($in{ErrorMessage} has reason)
#
#       In: $in{Frames}            -- user's unsanitized "Frames:"
#           $in{BatchFrames}       -- user's unsanitized "Batch Frames:"
#           $in{BatchClip}         -- user's "BatchClip:" (yes|no)
#                               _
#      Out: $in{BatchStart}      \    Calculated values render script needs.
#           $in{BatchEnd},        >-- Start/End are used for clipping,
#           $in{BatchInc}       _/    Inc is step rate passed to the renderer.
#           $in{Frames}            -- user's *unsanitized* "Frames:"
#           $in{BatchFrames}       -- Sanitized "Batch Frames:"
#
sub BatchStepSubmit($$)
{
    my ($in, $newframespec) = @_;

    $$in{BatchFrames} ||= 1;                    # batch must be /something/
    $$in{BatchStart}  ||= 0;
    $$in{BatchEnd}    ||= 0;
    $$in{BatchInc}    ||= 0;

    $$in{BatchFrames} = ( $$in{BatchFrames} eq "" || $$in{BatchFrames} eq "-" ) ? 1 : $$in{BatchFrames} + 0;
    $$in{BatchFrames} = abs($$in{BatchFrames});

    # NO BATCHING?
    #    Short circuit -- no reason to do all this
    #
    if ( $$in{BatchFrames} == 1 )
    {
        $$newframespec = $$in{Frames};
        return(0);
    }
    my ($sfrm, $efrm, $ifrm);

    # PARSE USER SPECIFIED FRAME RANGE
    if ( $$in{Frames} =~ /^([-+]*[0-9.]*)-([-+]*[0-9.]*),([-+]*[0-9.]*)$/ )
        { ($sfrm, $efrm, $ifrm) = ($1, $2, $3); }       # FRAME RANGE WITH INCREMENT
    elsif ( $$in{Frames} =~ /^([-+]*[0-9.]*)-([-+]*[0-9.]*)$/ )
        { ($sfrm, $efrm, $ifrm) = ($1, $2, 1); }        # FRAME RANGE, NO INCREMENT
    elsif ( $$in{Frames} =~ /^([+-]*[0-9.]*)$/ )
        { ($sfrm, $efrm, $ifrm) = ($1, $1, 1); }        # SINGLE FRAME
    else
    {
        # NOT ALLOWED FOR BATCHING
        $$in{ErrorMessage} = "\n*** BATCH FRAMES ERROR ***\n".
	                     "\n".
                             "When batching frames, you can only specify\n".
                             "simple frame ranges like '1-100' or '1-100,5'.\n".
                             "Please change your 'Frames' setting.\n";
        return(-1);
    }

    # SANITIZE $ifrm
    my $new_ifrm = ( ( $sfrm > $efrm && $ifrm > 0 ) || 
                     ( $sfrm < $efrm && $ifrm < 0 ) ) ? -($ifrm) : ($ifrm);

    # REWRITE FRAME RANGE TO TAKE INTO ACCOUNT BATCH
    $$newframespec = sprintf("%s-%s,%s", $sfrm, $efrm, ($$in{BatchFrames} * $new_ifrm));

    # SAVE BATCH RANGE
    $$in{BatchStart} = $sfrm;
    $$in{BatchEnd}   = $efrm;
    $$in{BatchInc}   = $new_ifrm;

    return(0);
}

# HANDLE COMPUTING BATCHFRAMES FOR RENDER
#     $1 - REFERENCE: %in 
#     $2 - current frame (ie. $ENV{RUSH_FRAME})
#     Returns: ($sfrm, $efrm, $ifrm)
#
sub BatchStepRender($$)
{
    my ($in,$frame) = @_;

    # NO BATCHING?
    #    Render /only/ the current frame; $inc /always/ 1
    #
    if ( ! defined($$in{BatchFrames}) || $$in{BatchFrames} == 1 )
        { return($frame, $frame, 1); }

    my ($sfrm, $efrm, $ifrm);
    my $tinc = ($$in{BatchFrames}-1) * $$in{BatchInc};  # total increment
    # -1 needed for /F:1-10,1 batch=2

    $sfrm = $frame;
    $efrm = $frame + $tinc;
    $ifrm = $$in{BatchInc};

    # BATCH CLIP
    #    Avoid rendering leftover frames at end of batch
    #
    if ( $$in{BatchClip} eq "yes" )
    {
        if ( $sfrm < $efrm && $sfrm <= $$in{BatchEnd} && $efrm >= $$in{BatchEnd} )
            { $efrm = $$in{BatchEnd}; }         # NORMAL FORWARD RANGE
        elsif ( $sfrm > $efrm && $sfrm >= $$in{BatchEnd} && $efrm <= $$in{BatchEnd} )
            { $efrm = $$in{BatchEnd}; }         # BACKWARD FRAME RANGE
    }

    return($sfrm,$efrm,$ifrm);
}

# RETURNS PATHNAME OF THE HELP DIRECTORY FOR THIS SCRIPT
#     $1 - optional filename to be appended to directory.
#     Should be a 'help' subdir of the script file's directory.
#
sub HelpDir($)
{
    my $h = $G::self;
    $h =~ s%\\%/%g;                                     # \path\file -> /path/file
    $h =~ s%/[^/]*$%%g;                                 # /path/submit-x.pl -> /path
    $h =~ s%/Applications/[^.]*.app/.*%%g;              # /path/Applications..-> /path
    $h =~ s%/[^.]*.app/.*%%g;                           # /path/foo.app/..-> /path
    $h .= "/help";                                      # /path -> /path/help
    if ( ! -d $h )
        { $h = "$ENV{RUSH_DIR}/examples/help"; }        # use rush dir if ENOENT
    if ( defined($_[0]) )
        { $h = "$h/$_[0]"; }
    return($h);
}

# PRESENT A 'STANDARD' SUBMIT INPUT FORM
#    Converts the "Key: ______" ascii representation of input forms
#    into commands suitable for rush's 'input' program to digest.
#        $1 - helpfile, eg. "submit-maya.html"
#        $2 - text layout form
#        $3 - REFERENCE: returned ".in" file to supply to input(1)
#
sub CreateInputForm($$$)
{
    my ($helpfile, $form, $out) = @_;
    $helpfile = HelpDir($helpfile);
    my %prompts;			# input prompt hash
    my $tprompts = 0;			# total entries in %prompts
    my $title = "?";			# title of input form window
    my $pageheight = 0;			# keeps track of page height
    my $saveid = "none";
    my $x = 0, $y = 25;			# starting x/y positions
    my $rawmode = 0;
    my $rawhtmlmode = 0;
    my $box_i = -1;			# index of last box being defined
    my $has_tabs = 0;			# 1=tabs are being used
    my $prompt_x = 140;			# left edge of prompts
    my $prompttab_x = $prompt_x + 10;	# left edge of prompts w/tabs
    my $prompt2_x = 440;		# left edge of prompts in 2nd col
    my $prompt2tab_x = $prompt2_x + 55;	# left edge of prompts in 2nd col w/tabs
    my $win_w = 700;			# width of window
    my $wintab_w = $win_w + 10 + 10;	# width of window w/tabs
    my $box_x = 10;			# left edge of '=' boxes
    my $boxtab_x = $box_x + 7;		# left edge of '=' boxes w/tabs
    my $box_w = $win_w - 35;     	# width of '=' boxes
    my $boxtab_w = $wintab_w - 45;     	# width of '=' boxes w/tabs

    # PARSE EACH LINE OF THE TEXT LAYOUT
    foreach my $s ( split('\n', $form, -1 ) )
    {
        # SKIP COMMENTS
        if ( $s =~ /^[ \t]*#/ )
            { next; }

        # HANDLE RAW-INPUT MODE
        #    This allows caller to insert raw input(1) commands
        #    into the screen definition.
        #
        if ( $s =~ m%^<<RAW-INPUT>>% )		# RAW ON
            { $rawmode = 1; $prompts{$tprompts}{Type} = "<<raw-input>>"; next; }
        elsif ( $s =~ m%^<</RAW-INPUT>>% )	# RAW OFF
            { $rawmode = 0; $tprompts++; next; }
        elsif ( $rawmode )			# RAW PARSING
            { $prompts{$tprompts}{Raw} .= $s."\n"; next; }

        # IGNORE RAW HTML MODES
        #    This allows caller to insert raw html commands
        #    into the screen definition. In this context,
	#    these need to be parsed away to be ignored.
        #
        if ( $s =~ m%^<<RAW-HTML-INPUT>>% )		# RAW HTML ON
            { $rawhtmlmode = 1; next; }
        elsif ( $s =~ m%^<</RAW-HTML-INPUT>>% )		# RAW HTML OFF
            { $rawhtmlmode = 0; next; }
        elsif ( $rawhtmlmode )				# (skip)
            { next; }

        if ( $s =~ /^[ \t]*$/ )	# empty line?
        {
            $prompts{$tprompts}{Type} = "emptybox";
            $prompts{$tprompts}{Name} = "emptybox #$tprompts";
            $prompts{$tprompts}{X} = 0;
            $prompts{$tprompts}{Y} = $y;
            $prompts{$tprompts}{H} = 8;
            $prompts{$tprompts}{W} = 8;
            if ( $has_tabs ) { $prompts{$tprompts}{X} += 15; }
            $tprompts++;
            $yinc = 8;
            $y += 8;
            next;
        }

        my $hcol = 0; 
        my $maxyinc = 0;
        foreach ( split(/\|/, $s) )
        {
            my $yinc = 0;

            # Count horizontal columns
            ++$hcol;
            $x = ( $hcol == 1 ) ? $prompt_x : $prompt2_x;

            if ( /^=/ )
            {
                s/^=/ /;
                if ( $box_i == -1 )
                {
                    # NEW BOX
                    $box_i = $tprompts;
                    $prompts{$tprompts}{Type} = "box";
                    $prompts{$tprompts}{Y1} = $y - 5;	# -5: box starts above
                    $prompts{$tprompts}{Y2} = $y + 5;
                    $prompts{$tprompts}{W} = $box_w;
                    $tprompts++;
                }
                else
                {
                    # SUBSEQUENT ITEMS IN BOX
                    $prompts{$box_i}{Y2} = $y + 5;
                }
            }
            else
            {
                # STOP DEFINING BOX
                $box_i = -1;
            }

            # print "Working on $_\n";

            # HANDLE AN IMAGE EMBEDDED SOMEWHERE IN THE LINE
            if ( /(.*)<<IMAGE="(.*)" WH=(\d+)x(\d+)>>/ )
            {
                $prompts{$tprompts}{Type} = "image";
                $prompts{$tprompts}{Filename} = $2;
                $prompts{$tprompts}{X} = (length($1) * 9);
                $prompts{$tprompts}{Y} = $y;
                $prompts{$tprompts}{W} = $3;
                $prompts{$tprompts}{H} = $4;
                $tprompts++;
                s/<<IMAGE=[^>]*>>//g;
            }

            if ( /<<TITLE>> "(.*)"/ )
                { $title = $1; }
            elsif ( /<<ENDPAGE>>/ )
            {
                $pageheight = $y;
                if ( $has_tabs ) { $pageheight += 20; }
            }
            elsif ( /<<HEADING>>\s+"(.*)"/ )
            {
                $prompts{$tprompts}{Type} = "heading";
                $prompts{$tprompts}{Name} = $1;
                $prompts{$tprompts}{Y} = $y;
                $tprompts++;
                $yinc = 30;
            }
            elsif ( /<<SUBHEADING-CENTER>>\s+"(.*)"/ )
            {
                $prompts{$tprompts}{Type} = "subheading-center";
                $prompts{$tprompts}{Name} = $1;
                $prompts{$tprompts}{Y} = $y;
                $tprompts++;
                $yinc = 30;
            }
            elsif ( /<<SUBHEADING-LEFT>>\s+"(.*)"/ )
            {
                $prompts{$tprompts}{Type} = "subheading-left";
                $prompts{$tprompts}{Name} = $1;
                $prompts{$tprompts}{Y} = $y;
                $tprompts++;
                $yinc = 30;
            }
            elsif ( /<<SAVE-ID>>\s+"(.*)"/ )
            {
                $saveid = $1;
            }
            elsif ( /<<SUBMIT>>/ )
            {
                $prompts{$tprompts}{Type} = "submit";
                $prompts{$tprompts}{Y} = $y;
                $tprompts++;
                $yinc = 26;
            }
            elsif ( /<<SUBMITDEFAULTS>>/ )
            {
                $prompts{$tprompts}{Type} = "submitdefaults";
                $prompts{$tprompts}{X} = $x;
                $prompts{$tprompts}{Y} = $y;
                $prompts{$tprompts}{H} = 26;
                $yinc = 15;
                if ( $has_tabs )
                    { $prompts{$tprompts}{Y} += 15; $yinc += 5; }
                $tprompts++;
            }
            elsif ( /<<TAB>>\s+"(.*)"/ )
            {
                $prompts{$tprompts}{Type}   = "tab";
                $prompts{$tprompts}{Name}   = $1;
                $prompts{$tprompts}{Y}      = 45;				# tab y pos
                $prompts{$tprompts}{TabTop} = $prompts{$tprompts}{Y} + 35;	# top of inside of tabgroup
                $y = $prompts{$tprompts}{TabTop};				# y: top of tabgroup
                $yinc = 0;
                $tprompts++;

                $has_tabs = 1;
                $win_w = $wintab_w;			# wider window for tabs
                $prompt_x = $prompttab_x;		# move prompts over
                $prompt2_x = $prompt2tab_x;		# move prompts over
                $box_x = $boxtab_x;			# move boxes over
                $box_w = $boxtab_w;			# adjust box widths
            }
            # HANDLE A TYPICAL CHOOSER
            elsif ( /^[ \t]*([^:]*): "([^"]*)" (.*)$/ )
            {
                my ($prompt, $choice, $options) = ($1, $2, $3);
                $options =~ s/^\s+//; 
                $options =~ s/\s+$//;
                my $dbase = $prompt; 
		if ( $prompt =~ m/<(.*)\>$/ ) 		# Alternate language spec? eg. "alt-language<DbaseName>"
		{
		    $dbase = $1; 			# "フレーム範囲<Frames>:" -> "Frames"
		    $prompt =~ s/\<.*\>$//;		# "フレーム範囲<Frames>:" -> "フレーム範囲"
		}
                $dbase =~ s/[\s+?]//g;			# "Scene Path?" -> "ScenePath"
                $dbase =~ s/\([^)]*\)//g;		# "Memory (kb)" -> "Memory"

                if ( $choice =~ /,_$/ ) 
                { 
                    # INPUTCHOICE? eg. Foo: "one,two,three,_"
                    $prompts{$tprompts}{Type} = "inputchoice";
                    $choice =~ s/,_$//;
                }
                else
                {
                    # CHOICE? eg. Foo: "one,two,three"
                    $prompts{$tprompts}{Type} = "choice";
                }

                $prompts{$tprompts}{Name} = $dbase;
                $prompts{$tprompts}{Prompt} = $prompt;
                $prompts{$tprompts}{Choices} = $choice;
                $prompts{$tprompts}{Options} = $options;
                $prompts{$tprompts}{X} = $x;
                $prompts{$tprompts}{Y} = $y;
                $tprompts++;

                $yinc = (26 + 3);
            }
            # HANDLE A TYPICAL INPUT FIELD
            elsif ( /^[ \t]*([^:]*): (_[_]*)(.*)$/ )
            {
                my ($prompt, $field, $options) = ($1, $2, $3);
                $options =~ s/^\s+//;
                $options =~ s/\s+$//;

                my $dbase = $prompt; 
		if ( $prompt =~ m/<(.*)\>$/ ) 		# Alternate language spec? eg. "alt-language<DbaseName>"
		{
		    $dbase = $1; 			# "フレーム範囲<Frames>:" -> "Frames"
		    $prompt =~ s/\<.*\>$//;		# "フレーム範囲<Frames>:" -> "フレーム範囲"
		}
                $dbase =~ s/[\s+?]//g;			# "Scene Path?" -> "ScenePath"
                $dbase =~ s/\([^)]*\)//g;		# "Memory (kb)" -> "Memory"

                # BROWSER? USE "inputfilename"
                if ( $options =~ /Browse(.*)/ )
                {
                    my $filter = $1;
                    $prompts{$tprompts}{Type} = "inputfilename";

                    # PARSE OPTIONAL FILTER, eg. Browse"*.{db,scn}"
                    if ( $filter =~ /^"([^"]*)"/ )
                        { $prompts{$tprompts}{Filter} = $1; }
                    else
                        { $prompts{$tprompts}{Filter} = "*"; }
                }
                else
                    { $prompts{$tprompts}{Type} = "input"; }

                $prompts{$tprompts}{Name} = $dbase;
                $prompts{$tprompts}{Prompt} = $prompt;
                $prompts{$tprompts}{Size} = length($field);
                $prompts{$tprompts}{Options} = $options;
                $prompts{$tprompts}{X} = $x;
                $prompts{$tprompts}{Y} = $y;
                $tprompts++;

                $yinc = (26 + 3);
            }
            # HANDLE A COMPLETE LINE OF UNDERBARS (NO PROMPT)
            #     This indicates a continuation of a multiline prompt
            #
            elsif ( /^[ \t]*(_[_]*)$/ )
            {
                $tprompts--;			# adjust previous entry
                $prompts{$tprompts}{Type} = "inputmultiline";
                if ( ! defined($prompts{$tprompts}{Lines} ) )
                    { $prompts{$tprompts}{Lines} = 1; }
                $prompts{$tprompts}{Lines}++;
                $yinc = 28;				# height of line + sep
                $tprompts++;
            }

            # ENLARGE BY HIGHEST 'yinc'
            $maxyinc = ( $yinc > $maxyinc ) ? $yinc : $maxyinc;
        }
        $y += $maxyinc;

        # BOX BEING DEFINED? ENLARGE
        if ( $box_i != -1 )
            { $prompts{$box_i}{Y2} += $maxyinc; }
    }

    # BEGIN DEFINING THE '.in' FILE FOR THE INPUT PROGRAM
    my $wincol = ( $G::input =~ / -P/ ) ? 46 : 49;
    $$out = <<"EOF";
    window
    {
	name   "$title"
	xysize $win_w $pageheight
	color  $wincol
	resizable
	menubar
	scroll 1
	saveid "$saveid"
    }
    xy $prompt_x 25
EOF

    # SECOND PASS: LOOP THROUGH THE INPUT PROMPTS
    my $lastxsize = -1;
    for ( $t=0; $t<$tprompts; $t++ )
    {
        if ( $prompts{$t}{Type} eq "<<raw-input>>" )
	{
	    $$out .= $prompts{$t}{Raw};
	    next;
	}

        if ( $prompts{$t}{Type} eq "heading" )
	{
	    my $labelsize = 32;
	    my $xpos = $prompt_x;
	    my $ypos = $prompts{$t}{Y};
	    if ( $has_tabs )
	    {
	        $labelsize = 24;
		$xpos = 10;
		$ypos -= 8;
	    }
	    $$out .= <<"EOF";
    box
    {
	name      "$prompts{$t}{Name}"
	labelsize $labelsize
	align     0
	type      0
	labeltype 4
	labelfont 0
	xy        $xpos $ypos
	xysize    600 30
	boxaround 0 0
    }
EOF
        }
        elsif ( $prompts{$t}{Type} eq "subheading-center" )
	{
	    my $W = $win_w - 10 - 10;
	    my $X = 10;
	    if ( $has_tabs ) { $X += 10; $W -= 20; }
	    $$out .= <<"EOF";
    box
    {
	name      "$prompts{$t}{Name}"
	labelsize 20
	align     16   # inside|center
	type      0
	labeltype 4
	labelfont 0
	xy        $X $prompts{$t}{Y}
	xysize    $W 32
    }
EOF
        }
        elsif ( $prompts{$t}{Type} eq "subheading-left" )
	{
	    my $W = $win_w - 10 - 10;
	    my $X = 10;
	    if ( $has_tabs ) { $X += 10; $W -= 20; }
	    $$out .= <<"EOF";
    box
    {
	name      "$prompts{$t}{Name}"
	labelsize 20
	align     20   # inside|left
	type      0
	labeltype 4
	labelfont 0
	xy        $X $prompts{$t}{Y}
	xysize    $W 32
    }
EOF
        }
        elsif ( $prompts{$t}{Type} eq "image" )
	{
	    my $x = $prompts{$t}{X};
	    my $y = $prompts{$t}{Y};
	    my $w = $prompts{$t}{W};
	    my $h = $prompts{$t}{H};
	    $$out .= <<"EOF";
    # IMAGE
    box
    {
	xywh  $x $y $w $h
	image "$prompts{$t}{Filename}"
	align 0
    }
EOF
	}
        elsif ( $prompts{$t}{Type} eq "box" )
	{
	    my $y = $prompts{$t}{Y1};
	    my $w = $prompts{$t}{W};
	    my $h = $prompts{$t}{Y2} - $y;
	    my $boxcol = ( $G::input =~ / -P/ ) ? 48 : 50;
	    $$out .= <<"EOF";
    # GRAY BOX
    box
    {
	align     0
	type      1
	labeltype 4
	labelfont 0
	color     $boxcol
	xywh      $box_x $y $w $h
    }
EOF
	}
        elsif ( $prompts{$t}{Type} eq "emptybox" )
	{
	    my ($x,$y,$w,$h) = ( $prompts{$t}{X}, $prompts{$t}{Y}, $prompts{$t}{W}, $prompts{$t}{H} );
	    $$out .= <<"EOF";
    # EMPTY 'SEPARATOR' BOX
    box
    {
	align     0
	type      0		# use '1' for debugging
	color     $t
	xywh      $x $y $w $h
    }
EOF
	}
        elsif ( $prompts{$t}{Type} eq "tab" )
	{
	    # tab width: -10: left margin, -10: right margin
	    # tab height: -25:top margin, -60=bottom margin (submit buttons)
	    my $width = $win_w - 10 - 10;
	    my $height = $pageheight - 25 - 60;	# height of tabgroup
	    my $boxy = $prompts{$t}{Y} + 27;	# box in upper left sets scroller's top
	    my $tabcol = ( $G::input =~ / -P/ ) ? 46 : 48;
	    $$out .= <<"EOF";
    geltab
    {
	name           "$prompts{$t}{Name}"
	xysize         $width $height
	xy             10 $prompts{$t}{Y}
        visible_focus  0
        scroll
	color          $tabcol
	boxtype        6	# thin up box
    }
    box
    {
	align     0
	type      0		# use '1' for debugging
	color     $t
	xywh      15 $boxy 8 8
    }
    xy 5 $prompts{$t}{TabTop}
EOF
	}
        elsif ( $prompts{$t}{Type} eq "choice" || 
		$prompts{$t}{Type} eq "inputchoice" )
	{
	    my $options = $prompts{$t}{Choices};
	    $options = "option    \"$options\"";
	    $options =~ s/,/"\n    option    "/g;
	    $$out .= <<"EOF";
    $prompts{$t}{Type}
    {
	name      "$prompts{$t}{Prompt}"
	dbname    "$prompts{$t}{Name}"
	$options
	xy        $prompts{$t}{X} $prompts{$t}{Y}
	xysize    140 24
	helpurl   "$helpfile#$prompts{$t}{Name}"
    }
EOF
	    if ( $prompts{$t}{Options} =~ /Update/ )
	    {
	        my ($ux,$uy) = ($prompts{$t}{X} + 140, $prompts{$t}{Y} + 2);
	        $$out .= <<"EOF";
    # UPDATE BUTTON
    button
    {
	xy        $ux $uy
	xysize    55 20
	name      "Update"
	labelsize 12
	updatecommand "perl $G::self -update $prompts{$t}{Name}"
    }
EOF
	    }
        }
        elsif ( $prompts{$t}{Type} eq "input" )
	{
	    my $xsize = $prompts{$t}{Size} * 10;
	    if ( $xsize != $lastxsize )
	    {
	        $$out .= "xysize $xsize 24\n";
		$lastxsize = $xsize;
	    }
	    $$out .= <<"EOF";
    input
    {
	name      "$prompts{$t}{Prompt}"
	dbname    "$prompts{$t}{Name}"
	labelsize 14
	helpurl   "$helpfile#$prompts{$t}{Name}"
	textfont  4		# courier
	xy        $prompts{$t}{X} $prompts{$t}{Y}
    }
EOF
	    if ( $prompts{$t}{Options} =~ /Update/ )
	    {
	        my ($ux,$uy) = ($prompts{$t}{X} + 170, $prompts{$t}{Y} + 2);
	        $$out .= <<"EOF";
    # UPDATE BUTTON
    button
    {
	xy      $ux $uy
	xysize  55 20
	name    "Update"
	labelsize 12
	updatecommand "perl $G::self -update $prompts{$t}{Name}"
    }
EOF
	    }
	}
        elsif ( $prompts{$t}{Type} eq "inputmultiline" )
	{
	    my $xsize = $prompts{$t}{Size} * 10;
	    my $h = $prompts{$t}{Lines} * 28;
	    $$out .= "xysize $xsize $h\n";
	    $$out .= <<"EOF";
    input
    {
	name      "$prompts{$t}{Prompt}"
	dbname    "$prompts{$t}{Name}"
	labelsize 14
	multiline
	helpurl   "$helpfile#$prompts{$t}{Name}"
	textfont  4		# courier
	xy        $prompts{$t}{X} $prompts{$t}{Y}
    }
    xysize $lastxsize 24
EOF

	    # <ShowHosts>? Add a button that shows hostgroups
	    if ( $prompts{$t}{Options} =~ /<ShowHosts>/ )	# Cpus: ______ ? <ShowHosts>
	    {
	        my $ux = $prompts{$t}{X} + $xsize - 80;
	        my $uy = $prompts{$t}{Y} - 20;
	        $$out .= <<"EOF";
    # 'Show Hosts' BUTTON
    button
    {
	xy      $ux $uy
	xysize  80 16
	name    "Show Hosts"
	labelsize 10
	system "perl $G::self -showhosts"
	systemflags "b"
    }
EOF
	    }
	}
        elsif ( $prompts{$t}{Type} eq "inputfilename" )
	{
	    my $helpbrowse_size = 100;
	    my $xsize = $prompts{$t}{Size} * 10;
	    if ( $xsize != $lastxsize )
	    {
	        $$out .= "xysize $xsize 24\n";
		$lastxsize = $xsize;
	    }
	    my $filebrowserupdatecommand = 
	        ( $prompts{$t}{Options} =~ /Update/ ) 
		    ? "filebrowserupdatecommand \"perl $G::self -update $prompts{$t}{Name}\""
		    : "# (no filebrowserupdatecommand)";
	    $$out .= <<"EOF";
    input
    {
	name              "$prompts{$t}{Prompt}"
	dbname            "$prompts{$t}{Name}"
	labelsize         14
	filebrowser       yes
	filebrowserfilter "$prompts{$t}{Filter}"
	$filebrowserupdatecommand
	helpurl           "$helpfile#$prompts{$t}{Name}"
	textfont          4		# courier
	xy                $prompts{$t}{X} $prompts{$t}{Y}
    }
EOF
	    if ( $prompts{$t}{Options} =~ /Update/ )
	    {
		#  _________________   _   ______   ______
		# |_________________| |?| |Browse| |Update|
		#  <---------------> <------------> <---->
		#       xsize              100        55
		#
	        my ($ux,$uy) = ($prompts{$t}{X} + $xsize + 100, $prompts{$t}{Y} + 2);
		$lastxsize = $xsize + 100 + 55 + 5;

	        $$out .= <<"EOF";
    # UPDATE BUTTON
    button
    {
	xy        $ux $uy
	xysize    55 20
	name      "Update"
	labelsize 12
	updatecommand "perl $G::self -update $prompts{$t}{Name}"
    }
EOF
	    }
	}
        elsif ( $prompts{$t}{Type} eq "submit" )
	{
	    $$out .= <<"EOF";
    xy 440 $prompts{$t}{Y}
    submit
    {
	submitname      "Submit"
	cancelname      "Cancel"
	submitcmd       "perl $G::self -submit "
	showfail        1
	submitcolor     230
	cancelcolor     49
	cancelpushcolor 1
    }
EOF
	}
        elsif ( $prompts{$t}{Type} eq "submitdefaults" )
	{
	    # PUT SUBMIT BUTTONS /OUTSIDE/ OF SCROLL WINDOW
	    if ( $has_tabs )
	        { $$out .= "window.begin\n"; }
	    my $defaults_col = ( $G::input =~ / -P/ ) ? 132 : "-794787840";	# 0xd0a08000
	    my $submit_col   = ( $G::input =~ / -P/ ) ? 230 : "-1596401664";	# 0xa0d8d800
	    $$out .= <<"EOF";
    xy $prompts{$t}{X} $prompts{$t}{Y}
    xyinc +332 0
    submit
    {
	submitname      "Submit"
	cancelname      "Cancel"
	submitcmd       "perl $G::self -submit "
	showfail        1
	submitcolor     $submit_col
	cancelcolor     49
	cancelpushcolor 1
    }
    xyinc -95 -23
    button
    {
	name          "Help"
	xysize        90 24
	helpurl       "$helpfile"
    }
    xyinc -95 -27
    button
    {
	name          "Defaults"
	color         $defaults_col
	xysize        90 24
	updatecommand "perl $G::self -defaults"
    }
    xyinc -142 0
EOF
	}
    }
}

# CREATE THE USER'S SUBMIT DIRECTORY
#     Returns -1 on error, error window is presented to user.
#
sub CreateDotRushDir()
{
    # CREATE USER'S SUBMIT DIR IF DOESN'T EXIST
    if ( ! -d $G::dotrushdir )
    {
        unless ( mkdir($G::dotrushdir, 0777) )
        {
            ErrorWindow("ERROR: Could not create '$G::dotrushdir': $!\n".
                        "(Check write permissions on parent directory)\n");
            return(-1);
        }
        # WINDOWS: OPEN ACLS
        if ( $G::iswindows )
        {
            my $dirname = $G::dotrushdir; $dirname =~ s%/%\\%g;
            system("cacls $dirname /e /c /g everyone:f");
        }
    }

    # CHECK FOR WRITE PERMISSION
    #     If none, try to open them up
    if ( ! -w $G::dotrushdir )
    {
        chmod(0777, $G::dotrushdir);
        if ( ! -w $G::dotrushdir )
        {
            ErrorWindow("ERROR: No write permission to '$G::dotrushdir'\n".
                        "(Please make this directory writeable)\n");
            return(-1);
        }
    }
    return(0);
}

# PRESENT THE INPUT FORM TO THE USER
#    $1 - ascii representation of the input form.
#         This format is not documented currently -- RTSL.
#    RUSH_QCCHECK: set to '1' to do quality control checks on Defaults.
#
sub PresentInputForm($)
{
    my ($form) = @_;
    my $dbasefile = "$G::dotrushdir/$G::progname.in";

    # CREATE USER'S RUSH DIR
    if ( CreateDotRushDir() < 0 )
        { return(1); }

    # CREATE INPUT DATABASE FILE, BASED ON ABOVE ASCII LAYOUT INFO
    my $out;
    CreateInputForm("${G::progname}.html", $form, \$out);
    unless ( open(DB, ">$dbasefile") )
        { ErrorWindow("$dbasefile: $!\n"); return(1); }
    print DB $out;
    close(DB);

    # NOW INVOKE GUI INPUT PROGRAM IN BACKGROUND WITH ABOVE DATABASE FILE
    #    SUBMIT button will invoke this script with "-submit"
    #
    my $cmd = "$G::input -d $dbasefile -H ${G::histfile} -f ${G::lastsubmit}";
    if ( $G::iswindows )
    {
        eval '
            # SUFFICIENT MAGIC TO OPEN "INPUT" W/OUT BLACK WINDOW
            use Win32::Process;
            my $pobj;
            $G::input =~ s%/%\\\\%g;                 # Create() wants backslashes
            my $cmd = $G::input; $cmd =~ s% .*%%;    # just the command, no args
            my $inputcmd = "$G::input -d $dbasefile -H ${G::histfile} -f ${G::lastsubmit}";
            my $err = Win32::Process::Create($pobj, "$cmd.exe",
                             $inputcmd, 0, NORMAL_PRIORITY_CLASS|CREATE_NO_WINDOW|DETACHED_PROCESS, ".");
            if ( $err == 0 )
            {
                my $errmsg = Win32::FormatMessage(Win32::GetLastError());
                $errmsg =~ s/\r//g;
                ErrorWindow("Executing: \'$cmd\'\nFull Command: \'$inputcmd\'\n$errmsg\n");
            }
            ';
	return(0);
    }
    unless ( exec($cmd) )
    {
        # COULDN'T OPEN INPUT PROGRAM? MUST NOT EXIST
	#    Complain to stderr; ErrorWindow() won't work.
	#
        print STDERR "Can't exec($G::input): $!\n";
	exit(1);
    }
    return(0);
}

# LOAD BATCH SCRIPT'S ENVIRONMENT SETTINGS INTO PERL ENVIRONMENT
#    $1 = batch script to load
#    Returns: $ENV{} modified as per batch script's settings.
#
sub LoadEnvFromDOS($)
{
    my ($batchfile) = @_;
    my $vars = `cmd /c "call $batchfile && set"`;
    foreach ( split(/\n/, $vars) )
        { if ( /(^[^=]*)=(.*)/ ) { $ENV{$1} = $2; } }
}

# LOAD A CSH SCRIPT'S ENVIRONMENT SETTINGS INTO PERL ENVIRONMENT
#    $1 = csh script to be 'sourced'
#    Returns: $ENV{} modified as per csh script's settings.
#
sub LoadEnvFromCsh($)
{
    my ($rcfile) = @_;
    my $vars = `csh -fc 'source $rcfile; printenv'`;
    foreach ( split(/\n/, $vars) )
        { if ( /(^[^=]*)=(.*)/ ) { $ENV{$1} = $2; } }
}

# DISPLAY AN IMAGE
#    $1 - image pathname
#    $2 - preferred viewer (can be "")
#
sub DisplayImage($$)
{
    my ($image, $prefview) = @_;

    if ( ! -e $image )
    {
        ErrorWindow("Can't view image -- it does not exist:\n$image");
        return(0);
    }

    # ABSOLUTE PATH SPECIFIED? INVOKE VERBATIM
    if ( $prefview =~ /\// )
        { system("$prefview $image"); return(0); }

    if ( $prefview eq "fcheck" )
    {
        if ( $G::ismac )
        {
            ### OSX
            if ( defined($ENV{MAYA_LOCATION}) )
                { system("open -a $ENV{MAYA_LOCATION}/Fcheck.app $image"); return(0); }
            else
            {
                my @fcheck = glob("/Applications/Alias/*/Fcheck.app");
                if ( defined ( $fcheck[0] ) )
                    { system("open -a $fcheck[0] $image"); return(0); }
            }
            # Fallthrough to os dependent approaches
        }
        elsif ( $G::iswindows )
        {
            my $cmd = "fcheck $image 2>&1";
            eval '
                # SUFFICIENT MAGIC TO OPEN FCHECK W/OUT BLACK WINDOW
                use Win32::Process;
                my $pobj;
                my $cmdexe = ( -e "c:/winnt/system32/cmd.exe" ) 
                                     ? \'c:\winnt\system32\cmd.exe\'
                                     : \'c:\windows\system32\cmd.exe\';
                my $err = Win32::Process::Create($pobj, $cmdexe, 
                                 "cmd.exe /c $cmd", 0, NORMAL_PRIORITY_CLASS|CREATE_NO_WINDOW, ".");
                if ( $err == 0 )
                {
                    my $errmsg = Win32::FormatMessage(Win32::GetLastError());
                    $errmsg =~ s/\r//g;
                    ErrorWindow("Executing: \'$cmdexe /c $cmd\'\n$errmsg\n");
                }
                ';
            return(0);
        }
        else
        {
	    # LINUX
	    #    Can't open fcheck without a tty in maya 6.0.1 or 6.5.
	    #    Seems to be fixed in Maya 7.0.1, broken in maya2008.. :/
	    #
	    system("$prefview $image");
	    return(0);
	}
    }

    if ( $prefview eq "shake" )
        { system("shake $image"); return(0); }

    if ( $prefview eq "nuke" )
        { system("nuke -v $image"); return(0); }

    # USE OS-DEPENDENT WAY OF VIEWING IMAGE
    if ( $G::ismac )
        { system("open $image"); return(0); }
    if ( $G::iswindows )
        { system("$image"); return(0); }
    if ( $G::islinux )
    {
        # LINUX/IRIX
        #     Fcheck won't run w/out a tty, use alternatives..
        #
        my $cmd = "";
           if ( -x "/usr/bin/display"   ) { $cmd = "display $image";           } # IMAGE MAGICK?
        elsif ( -x "/usr/bin/eog"       ) { $cmd = "eog $image";               } # EYE OF GNOME?
        elsif ( -x "/usr/bin/konqueror" ) { $cmd = "konqueror $image";         } # KDE/KONQUEROR?
        elsif ( -x "/usr/local/bin/xv"  ) { $cmd = "/usr/local/bin/xv $image"; } # XV
        if ( $cmd ne "" )
        {
            my $errmsg = `$cmd 2>&1`;
            if ( $errmsg ne "" )
                { ErrorWindow("Executed: $cmd\nERROR: $errmsg"); }
            exit(0);
        }
        ErrorWindow("Could not find display(1), eog(1), konqueror(1) or xv(1).\n".
                    "Modify DisplayImage() in .common.pl to support your linux image viewer.\n");
        exit(0);
    }
    if ( $G::isirix )
        { system("imgview $image"); return(0); }

    ErrorWindow("UNSUPPORTED OPERATING SYSTEM\n".
                "Modify DisplayImages() in .common.pl to support\n".
                "your operating system's image viewer.");
    return(0);
}

# END OF FILE
1