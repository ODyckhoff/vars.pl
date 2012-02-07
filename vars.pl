use strict;
use warnings;
use Irssi::TextUI;

BEGIN {
    use Storable;
    use Cwd;
#build undo and redo stack
    our (%config, %foo, $farg, $sarg, @varcmds, @undo, @redo);
    my $hashref;
    
    my $user = getpwuid($<);
    $config{'vardata_path'} = '/home/' . $user . '.irssi/scripts/varspl/';
    mkdir $config{'vardata_path'} unless -e $config{'vardata_path'};
    
    #move .vardata to its new home if it exists
    use File::Copy;
    move('/home/' . $user . '/.vardata', $config{'vardata_path'} . '/.vardata') if -e '/home/' . $user . '/.vardata';

    if(-e $config{'vardata_path'}.'.vardata') {
        (($hashref = retrieve($config{'vardata_path'}.'.vardata')) && (%foo = %{$hashref}));
        
        #backwards compatibility - replace spaces in variable names with _
        foreach my $key (sort keys %foo) {
            my $old = $key;
            if($key =~ s/\s/_/g) {
                Irssi::print("WARNING: Variable '$old' renamed to '$key', since spaces are no longer permitted in variable names.");
                $foo{$key} = $foo{$old};
                delete $foo{$old} && store(\%foo, $config{'vardata_path'}.'.vardata')
            }
        }
    }
    
}
our (%config, %foo, $farg, $sarg, @varcmds, @tabcmds, @undo, @redo);
our $pre;

@varcmds = ('mkvar', 'rmvar', 'varlist', 'varhelp', 'undo', 'redo', 'editvar', 'cpvar');
@tabcmds = ('mkvar', 'rmvar', 'editvar', 'cpvar');
our $build = join('|', @tabcmds);

sub stack_gen {
    my($undoCode, $undoText, $redoCode, $redoText) = @_;

    #first things first... since new action happening, clear redo buffer.
    @redo = ();

    my $ref = [[$undoCode, $undoText], [$redoCode, $redoText]];
    push(@undo, $ref);
}#build undo and redo stack

sub undo {
    if(!@undo) {
        Irssi::print('No tasks left in the undo buffer');
        return;
    }
    my $ref = pop(@undo);
    &{ @{ @{$ref}[0] }[0] };
    Irssi::print('Undo successful: ' . @{ @{$ref}[0] }[1]);
    push(@redo, $ref); 
}

sub redo {
    if(!@redo) {
        Irssi::print('No tasks left in the redo buffer');
        return;
    }
    my $ref = pop(@redo);
    &{ @{ @{$ref}[1] }[0] };
    Irssi::print('Redo successful: ' . @{ @{$ref}[1] }[1]);
    push(@undo, $ref);
}

sub tab_complete {
    my $testre = qr/^\/$build/; #only one regex to change.
    my ($strings, $window, $word, $linestart, $want_space) = @_;
    #Irssi::print("\$linestart: '$linestart'");
    #Irssi::print("\$word: '$word'");
    my $post;
    my $brace;
    my $primed = 0;
    if ($linestart =~ /$testre/) {
        #Irssi::print('condition 1');
        #build list of eligible words using $word.
        $post = $';
        #Irssi::print($post) if $post;
        return unless((!$post && $word !~ /\W/)
          ||(($post && $word =~ /\{\{((\w+)((?!\\\}\})|(?!\}\})))?$/) 
          && eval {$brace = 1; return 1}));
          #Irssi::print("still alive!");
    }
    elsif($word =~ /\{\{((\w+)((?!\\\}\})|(?!\}\})))?$/) {
        #Irssi::print('condition 2');
        $brace = 1;
    }
    else {
        @$strings = ();
        return;
    }

    @$strings = (); #clear out any old rubbish that may be lingering
    $pre = '';
    foreach my $key (sort { lc($a) cmp lc($b) } keys %foo) {
        $word =~ s/(.*)\{\{// if $brace;
        $pre = $1 if ($1 and $brace); 
        #Irssi::print("\$word: '$word'");
        #get all the stuff in front of {{ just in case
        #Irssi::print("pre: '$pre'");
        if($key =~ /^$word/i) {
            push(@$strings,
                ($pre   ? $pre : '') .
                ($brace ? '{{'.$key.'}}'
                       : $key)
            );
        }
    }
    $$want_space = 0;
    Irssi::signal_stop;
}      

sub cmd_mkvar {
    my ($data) = @_;
    $_ = $data;

    my @args = split(/\s/);
    if(scalar(@args) < 2) {
        Irssi::print('Syntax Error: ' . scalar(@args) == 1 ? 'Single' : 'No' . ' Argument Given');
        Irssi::print('Type /varhelp for command usage');
        return;
    }
    else {
        $farg = shift @args;
        $sarg = join(' ', @args);
        if($foo{$farg}) {
            Irssi::print("Error: variable '$farg' already exists. Use /editvar to overwrite");
            return;
        }
        if($farg =~ /\W/) {
            Irssi::print('Error: only alphanumeric characters (A-Z, a-z, 0-9 and _) are permitted in variable names.');
            return;
        }
    }

    while($sarg =~ /\G(?!\\)\{\{(\w+)(?!\\)\}\}/g) {
        my $match = $1;
        unless($foo{$match}) {
            Irssi::print('Inserted variable \'{{' . $match . '}}\' does not exist. Remember to backlslash (\{{ \}}) any variables you do not want interpreted. Command failed.');
            return;
        }
    }
    my $safe = loopcheck($sarg);
    if($safe eq 'ERROR') {
        return;
    }
    else {
        $foo{$farg} = $sarg;
        Irssi::print("Variable '$farg' succesfully saved with value '$sarg'");
        store(\%foo, $config{'vardata_path'}.'.vardata');
        
        #build undo and redo stack
        my $undoRef = sub {
                        delete $foo{$farg};
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $redoRef = sub {
                        $foo{$farg} = $sarg;
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $undoTxt = "Deleted variable '$farg' containing value: '$sarg'";
        my $redoTxt = "Recreated variable '$farg' containing value: '$sarg'";

        stack_gen($undoRef, $undoTxt, $redoRef, $redoTxt);
    }
    return;
}

sub cmd_editvar {
    my ($data) = @_;
    $_ = $data;

    my @args = split(/\s/);
    if(scalar(@args) < 2) {
        Irssi::print('Syntax Error: ' . (scalar(@args) == 1 ? 'Single' : 'No') . ' argument given.');
        Irssi::print('Type /varhelp for command usage');
        return;
    }
    else {
        $farg = shift @args;
        $sarg = join(' ', @args);
        if(!$foo{$farg}) {
            Irssi::print("Error: variable '$farg' does not exist. Use /mkvar to create a new variable.");
            return;
        }
    }

    while($sarg =~ /\G(?!\\)\{\{(\w+)(?!\\)\}\}/g) {
        my $match = $1;
        unless($foo{$match}) {
            Irssi::print('Inserted variable \'{{' . $match . '}}\' does not exist. Remember to backlslash (\{{ \}}) any variables you do not want interpreted. Command failed.');
            return;
        }
    }
    my $tmp = $foo{$farg};
    $foo{$farg} = $sarg;
    my $safe = loopcheck($sarg);
    if($safe eq 'ERROR') {
        $foo{$farg} = $tmp;
        Irssi::print('Definition of \'' . $farg . '\' unchanged');
    }
    else {
        Irssi::print("Variable '$farg' succesfully saved with new value '$sarg'");
        store(\%foo, $config{'vardata_path'}.'.vardata');

        #build undo and redo stack
        my $undoRef = sub {
                        $foo{$farg} = $tmp;
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $redoRef = sub {
                        $foo{$farg} = $sarg;
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $undoTxt = "Value of variable '$farg' reverted from '$sarg' to '$tmp'.";
        my $redoTxt = "Value of variable '$farg' changed again from '$tmp' to '$sarg'";

        stack_gen($undoRef, $undoTxt, $redoRef, $redoTxt);
    }
    return;
}

sub cmd_cpvar {
    my ($data) = @_;
    $_ = $data;

    my @args = split(/\s/);
    if(scalar(@args) < 2 || scalar(@args) > 3) {
        Irssi::print('Syntax Error: ' . scalar(@args) . (scalar(@args) == 1 ? ' argument' : ' arguments') . 'given.');
        Irssi::print('Type /varhelp for command usage');
        return;
    }

    my $flag;
    my $var = shift(@args);
    if($var eq '-f') {
        $flag = $var;
        $var = shift(@args);
    }
    elsif($var =~ /\W/) {
        Irssi::print("Error: '$var' is not a valid flag or variable name.");
        Irssi::print('Type /varhelp for command usage');
        return;
    }
    
    unless($foo{$var}) {
        Irssi::print("Error: variable '$var' does not exist. Cannot copy.");
        return;
    }
    
    my $newvar = shift(@args);
    my $tmp;
    if($foo{$newvar}) {
        unless($flag) {
            Irssi::print("Error, '$newvar' already exists. Use '-f' flag (/cpvar -f foo bar) if you wish to overwrite.");
            return;
        }
        else {
            $tmp = $foo{$newvar};
            $foo{$newvar} = $foo{$var};
            Irssi::print("Contents of variable '$var' successfully copied to existing variable '$newvar'.");
            store(\%foo, $config{'vardata_path'}.'.vardata');
        }
    }
    else {
        $foo{$newvar} = $foo{$var};
        Irssi::print("Contents of variable '$var' successfully copied to new variable '$newvar'.");
        store(\%foo, $config{'vardata_path'}.'.vardata');
    }

    #build undo and redo stack
    if($tmp) {
        my $undoRef = sub {
                        $foo{$newvar} = $tmp;
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $redoRef = sub {
                        $foo{$newvar} = $foo{$var};
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $undoTxt = "Old value of variable '$newvar' restored from '".$foo{$var}."' to '$tmp'.";
        my $redoTxt = "New value of variable '$newvar' restored from '$tmp' to '".$foo{$var}."'.";

        stack_gen($undoRef, $undoTxt, $redoRef, $redoTxt);
    }
    else {
        my $undoRef = sub {
                        delete $foo{$newvar};
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $redoRef = sub {
                        $foo{$newvar} = $foo{$var};
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $undoTxt = "Variable '$newvar' removed.";
        my $redoTxt = "New variable '$newvar' restored with value '".$foo{$var}."'.";

        stack_gen($undoRef, $undoTxt, $redoRef, $redoTxt);
    }
    return;
}

sub cmd_rmvar {
    my ($data) = @_;
    my $tmp = $foo{$data};
    if(delete $foo{$data} && store(\%foo, $config{'vardata_path'}.'.vardata')) {
        Irssi::print("Variable '$data' has been successfully deleted");

        #build undo and redo stack
        my $undoRef = sub {
                        $foo{$data} = $tmp;
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $redoRef = sub {
                        delete $foo{$data};
                        store(\%foo, $config{'vardata_path'}.'.vardata');
                      };
        my $undoTxt = "Deleted variable '$data' restored with value '$tmp'.";
        my $redoTxt = "Variable '$data' deleted again.";
    }
    else {
        Irssi::print("Variable '$data' not found");
    }
    return;
}

sub varreplace {
    return if not %foo;
    my ($data, $server, $witem) = @_;
    #my $emit = Irssi::signal_get_emitted();
    #Irssi::print($emit);
    #Irssi::print("data in varreplace sub: $data");
    if($data =~ /^\/(.*?)\s/) {
        my @matches = grep(/$1/, @varcmds);
        #Irssi::print(join(', ', @matches));
        if(@matches) {
            #Irssi::print("$1 is a varcmd");
            return;
        }
    }
    if (!$server || !$server->{connected}) {
        Irssi::print("Not connected to server");
        return;
    }
    if ($data) {
        #Irssi::print("about to init loopcheck");
        $data = loopcheck($data);
        #Irssi::print("loopcheck fin - data = $data");
        if($data ne 'ERROR') {
            $data =~ s/\\\{\{/{{/g;
            $data =~ s/\\\}\}/}}/g;
            Irssi::signal_continue($data, $server, $witem);
        }
        else {
            Irssi::signal_stop();
        }
    }
    return;
}

sub loopcheck {
    my ($data) = @_;
    #Irssi::print("data: $data");
    my @loop;
    while($data =~ /(?!\\)\{\{(\w+)(?!\\)\}\}/) {
        #Irssi::print("why am I here? - pre: $`; match: $&; post: $'");
        my $var = $1;
    
        #first, we ensure the variable exists in the first place.
        unless($foo{$var}) {
            Irssi::print('Inserted variable \'{{' . $var . '}}\' does not exist. Remember to backlslash (\{{ \}}) any variables you do not want interpreted. Supressed.');
            return 'ERROR';
        }

        #Now, we start making sure that there aren't any silly loops and such occurring, e.g. {{foo}} = {{bar}} and {{bar}} = {{foo}}.
        if(!grep(/^$var$/, @loop)) {
            push(@loop, $var);
            $data =~ s/\{\{$var\}\}/$foo{$var}/e;
        }
        else {
            #Yep, someone is being an idiot... Double slap them if this is an IRC event, since they've manually changed the contents of %foo
            Irssi::print('Loop detected in variable \'' . $var . '\'');
            return 'ERROR';
        }
        #now we clear out the loop, ready for the next variable (if any) to be checked
        @loop = ();
    }
        #Irssi::print("After loop: data = $data");
	return $data;
}

sub listvars {
    if(!%foo) {
        Irssi::print('No variables found');
        return;
    }
    Irssi::print('Listing all variables:');
    foreach my $key (sort {lc($a) cmp lc($b)} keys %foo) {
        Irssi::print($key . ': \'' . $foo{$key} . '\'');
    }
}

sub help {
    Irssi::print("\x02" . 'This is the vars.pl tool help:');
    Irssi::print('');
    Irssi::print("    \x02" . 'Creating a variable:');
    Irssi::print('        A variable name is made of one or more words, consisting only of alphanumeric characters or underscores');
    Irssi::print('        A variable name cannot begin or end with a space.');
    Irssi::print('        The value can be whatever the hell you please');
    Irssi::print('        Please comma separate your arguments as /mkvar \'name\', \'value\' using single or double quotes.');
    Irssi::print('        Please use the same quotes to start and end a single argument.');
    Irssi::print('        You may choose different quotes for different arguments, e.g. /mkvar \'foo\', "bar"');
    Irssi::print('        You must backslash escape your chosen quote mark, like /mkvar \'foo\', \'foo, \\\'bar\\\', baz\'');
    Irssi::print('        You may have multiple words as variable names, using alphanumeric characters, underscore and spaces');
    Irssi::print('        However, since the point is to reduce typing by setting large values to simple variables, this is somewhat silly.');
    Irssi::print('        You can do it anyway, but remember to backslash escape the necessary quotes etc.');
    Irssi::print('        This is the cool bit - you can include other pre-existing variables in the definition of a variable.');
    Irssi::print('        If the included variable doesn\'t exist beforehand, the command will fail. Backslash (\^) any carets you do not want interpreted.');
    Irssi::print("        \x02" . 'Also note that if you attempt to create a variable with the same name as a previously existing variable, that variable will be overwritten');

    Irssi::print("    \x02" . 'Removing a variable:');
    Irssi::print('        Use the /rmvar command followed by the variable name, e.g. \'/rmvar foo bar baz\' to remove \'foo bar baz\'');
    Irssi::print('        No quotes are necessary.');

    Irssi::print("    \x02" . 'Using variables');
    Irssi::print('        To use a variable simply wrap the name in between two control characters. (the ^ character)');
    Irssi::print('        For Example: This is a sentence with a ^variable^ embedded in it');
    Irssi::print('        If you use multiple ^ symbols per sentence anyway, I wouldn\'t worry, as if no match is found, no substitution is made');
    Irssi::print('        However, you will have to be a little careful of what you name your variables.');
    return;
}

Irssi::command_bind('mkvar', 'cmd_mkvar');
Irssi::command_bind('rmvar', 'cmd_rmvar');
Irssi::command_bind('editvar', 'cmd_editvar');
Irssi::command_bind('cpvar', 'cmd_cpvar');
Irssi::command_bind('varhelp', 'help');
Irssi::command_bind('varlist', 'listvars');
Irssi::command_bind('undo', 'undo');
Irssi::command_bind('redo', 'redo');
#Irssi::signal_add('send text', 'varreplace');
Irssi::signal_add('send command', 'varreplace');
Irssi::signal_add_first("complete word", 'tab_complete');
