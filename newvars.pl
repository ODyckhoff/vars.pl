use strict;
use warnings;
use Irssi::TextUI;

BEGIN {
    use Storable;
    our (%config, %foo, $farg, $sarg, @varcmds, @undo, @redo);
    my $hashref;
    
    my $user = getpwuid($<);
    Irssi::print($user);
    $config{'vardata_path'} = '/home/' . $user . '/.irssi/scripts/varspl';
    mkdir $config{'vardata_path'} unless -e $config{'vardata_path'};
    Irssi::print($!);
    
    #move .vardata to its new home if it exists
    use File::Copy;
    move('/home/' . $user . '/.vardata', $config{'vardata_path'} . '/.vardata') if -e '/home/' . $user . '/.vardata';

    if(-e $config{'vardata_path'}.'/.vardata') {
        (($hashref = retrieve($config{'vardata_path'}.'/.vardata')) && (%foo = %{$hashref}));
        
        #backwards compatibility - replace spaces in variable names with _
        foreach my $key (sort keys %foo) {
            my $old = $key;
            if($key =~ s/\s/_/g) {
                Irssi::print("WARNING: Variable '$old' renamed to '$key', since spaces are no longer permitted in variable names.");
                $foo{$key} = $foo{$old};
                delete $foo{$old} && store(\%foo, $config{'vardata_path'}.'/.vardata')
            }
        }
    }
    
}

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
        store(\%foo, $config{'vardata_path'}.'/.vardata');
        
        #build undo and redo stack
        my $undoRef = sub {
                        delete $foo{$farg};
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $redoRef = sub {
                        $foo{$farg} = $sarg;
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $undoTxt = "Deleted variable '$farg' containing value: '$sarg'";
        my $redoTxt = "Recreated variable '$farg' containing value: '$sarg'";

        stack_gen($undoRef, $undoTxt, $redoRef, $redoTxt);
    }
    return;
}

sub cmd_rmvar {
    my ($data) = @_;
    my $tmp = $foo{$data};
    if(delete $foo{$data} && store(\%foo, $config{'vardata_path'}.'/.vardata')) {
        Irssi::print("Variable '$data' has been successfully deleted");

        #build undo and redo stack
        my $undoRef = sub {
                        $foo{$data} = $tmp;
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $redoRef = sub {
                        delete $foo{$data};
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $undoTxt = "Deleted variable '$data' restored with value '$tmp'.";
        my $redoTxt = "Variable '$data' deleted again.";
    }
    else {
        Irssi::print("Variable '$data' not found");
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
        store(\%foo, $config{'vardata_path'}.'/.vardata');

        #build undo and redo stack
        my $undoRef = sub {
                        $foo{$farg} = $tmp;
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $redoRef = sub {
                        $foo{$farg} = $sarg;
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
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
    my $safe;
    if($foo{$newvar}) {
        unless($flag) {
            Irssi::print("Error, '$newvar' already exists. Use '-f' flag (/cpvar -f foo bar) if you wish to overwrite.");
            return;
        }
        else {
            $tmp = $foo{$newvar};
            $foo{$newvar} = $foo{$var};
            $safe = loopcheck($foo{$var});
            if($safe eq 'ERROR') {
                $foo{$newvar} = $tmp;
                undef($tmp);
                return;
            }   
            Irssi::print("Contents of variable '$var' successfully copied to existing variable '$newvar'.");
            store(\%foo, $config{'vardata_path'}.'/.vardata');
        }
    }
    else {
        $foo{$newvar} = $foo{$var};
        $safe = loopcheck($foo{$var});
        if($safe eq 'ERROR') {
            delete $foo{$newvar};
            return;
        }
        Irssi::print("Contents of variable '$var' successfully copied to new variable '$newvar'.");
        store(\%foo, $config{'vardata_path'}.'/.vardata');
    }

    #build undo and redo stack
    if($tmp) {
        my $undoRef = sub {
                        $foo{$newvar} = $tmp;
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $redoRef = sub {
                        $foo{$newvar} = $foo{$var};
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $undoTxt = "Old value of variable '$newvar' restored from '".$foo{$var}."' to '$tmp'.";
        my $redoTxt = "New value of variable '$newvar' restored from '$tmp' to '".$foo{$var}."'.";

        stack_gen($undoRef, $undoTxt, $redoRef, $redoTxt);
    }
    else {
        my $undoRef = sub {
                        delete $foo{$newvar};
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $redoRef = sub {
                        $foo{$newvar} = $foo{$var};
                        store(\%foo, $config{'vardata_path'}.'/.vardata');
                      };
        my $undoTxt = "Variable '$newvar' removed.";
        my $redoTxt = "New variable '$newvar' restored with value '".$foo{$var}."'.";

        stack_gen($undoRef, $undoTxt, $redoRef, $redoTxt);
    }
    return;
}

sub cmd_varlist {
    if(!%foo) {
        Irssi::print('No variables found');
        return;
    }
    Irssi::print('Listing all variables:');
    foreach my $key (sort {lc($a) cmp lc($b)} keys %foo) {
        Irssi::print($key . ': \'' . $foo{$key} . '\'');
    }
}

sub cmd_undo {
    if(!@undo) {
        Irssi::print('No tasks left in the undo buffer');
        return;
    }
    my $ref = pop(@undo);
    &{ @{ @{$ref}[0] }[0] };
    Irssi::print('Undo successful: ' . @{ @{$ref}[0] }[1]);
    push(@redo, $ref);
}

sub cmd_redo {
    if(!@redo) {
        Irssi::print('No tasks left in the redo buffer');
        return;
    }
    my $ref = pop(@redo);
    &{ @{ @{$ref}[1] }[0] };
    Irssi::print('Redo successful: ' . @{ @{$ref}[1] }[1]);
    push(@undo, $ref);
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

sub cmd_help {
    my $help = "For help on a specific command, e.g. /mkvar, type /help varspl mkvar.\n"
             . "This help is also available online at: http://users.aber.ac.uk/ord8/tech/non-web/varspl/";
    if ($_[0] eq 'varspl') {
        Irssi::print($help, MSGLEVEL_MSGS);
        Irssi::signal_stop;
    }
    elsif ($_[0] =~ /^varspl (\w+)$/) {
        if(exists &{'help_' . lc($1)}) {
            foreach(&{\&{'help_' . lc($1)}}()) {
                Irssi::print($_, MSGLEVEL_CLIENTCRAP);
            }
            Irssi::signal_stop;
        }
    }
}

sub help_mkvar {
    my @help = (
                     "",
                     "Synopsis: /mkvar name value",
                     "",
                     "This is the most important part of vars.pl, since this allows you to create all of your variables, "
                    ."which can be to insert something useful, such as an oft-used weird character that's difficult to type, "
                    ."or something silly and hilarious, or... well, whatever you feel like shoving into a variable, really.",
                     "",
                     "Usage:",
                     "Lets say you wanted to create our friendly 'foo' variable, and wanted to set its value to 'morning', "
                    ."as in the example above, you would simply type the command '/mkvar foo morning', and press Enter/Return. "
                    ."That's it! Done. It really is that easy.",
                     "",
                     "The way the command is parsed by the script is quite simple. /mkvar [name] [everything else]. "
                    ."The name must be made up of only 'word' characters, i.e. a-z, A-Z, 0-9 or _. If you insert a space, "
                    ."you terminate the variable name. Everything after the space is considered to be the value you wish to store "
                    ."in the variable. This means that, for example; you cannot create a variable called 'my mobile number' and "
                    ."insert the value '07#########'. Typing '/mkvar my mobile number 07#########' will result in a variable called "
                    ."'my' being created, which contains the value 'mobile number 07#########'. The value stored in the variable "
                    ."can be absolutely anything. If it's a typeable character, you can put it in. Note, however, that sequences "
                    ."such as '\\n' are interpreted literally, and will not insert a newline character into your variable. "
                    ."Attempting to insert an actual newline character will result in irssi's usual behaviour, which is to send "
                    ."the message off for processing, meaning that the intended value of your variable may be cut short.",
                     "",
                     "Now lets step up the game a little... If I found that greeting people was becoming tedious, and that typing "
                    ."Good {{foo}}! was too much like hard work, I could simply make it all into a variable by typing the command "
                    ."'/mkvar greet Good {{foo}}!'. Here's the slightly tricky bit, so pay attention: because of the way I "
                    ."designed this script, {{foo}} does not get converted into 'morning' when creating, or editing "
                    ."(see /editvar) variables. It does, however, become expanded when {{greet}} is used anywhere else. If I "
                    ."type {{greet}} into my input buffer and press return, the script first expands {{greet}} to 'Good {{foo}}!'"
                    .", and then looks up the value of {{foo}} and expands that, which results in 'Good morning!' being sent "
                    ."into the irssi core for the usual processing. However, as morning changes to afternoon, your greeting "
                    ."becomes less and less appropriate, so if you were to later change the value of 'foo' to 'afternoon', "
                    ."sending {{greet}} would now output 'Good afternoon!'.",
                     "",
                     "If you attempt to create a variable with the same name as one that already exists in the system, "
                    ."the script will present an error message in your status window, explaining that the chosen name already "
                    ."exists, and that you should make use of the /editvar command if you wish to overwrite the current value "
                    ."of that variable.",
                     "",
                );
    return @help;
}
sub help_rmvar {
    my @help = (
                     "",
                     "Synopsis: /rmvar variable",
                     "",
                     "This command should be fairly obvious. It is used to remove any variables which are no longer "
                    ."required, or which you added by accident. (For more on accidents, see /undo)",
                     "",
                     "Only thing left that's worth mentioning about this command, is that it will generate an error "
                    ."if you attempt to remove a variable that doesn't exist. Once the variable has been deleted, you "
                    ."cannot use it, or view it in the list of variables (see /varlist). This does not automatically "
                    ."mean that it is gone forever. It will be in your undo buffer until the script is unloaded, either "
                    ."manually using /script unload vars or forcibly via irssi terminating. If irssi terminates for "
                    ."whatever reason, I'm sorry, you can't get it back. You will have to recreate it again yourself, "
                    ."like you did the first time around (see /mkvar).",
                     "",
                     "TODO: decide on appropriate behaviour when a user removes a variable that another variable depended upon.",
                     "",
                );
    return @help;
}
sub help_editvar {
    my @help = (
                     "",
                     "Synopsis: /editvar variable new-value",
                     "",
                     "This variable works in almost exactly the same way as /mkvar. The only difference is the treatment of "
                    ."variables that do/don't exist. /mkvar will complain if you try to create a variable that already exists, "
                    ."whereas this command will complain if you try to edit the value of a command that doesn't exist. "
                    ."Tab-completion is supported by this command, so you can easily fill out the names of existing variables "
                    ."to avoid the script laughing at your futile efforts to not typo a name.",
                     "",
                     "Don't try any funny business. By \"funny\", I mean, for example, creating a variable called 'foo', then "
                    ."creating a variable called 'bar' which contains '{{foo}}', and then trying /editvar foo {{bar}}. "
                    ."vars.pl will see what you are doing and put its metaphorical foot down.",
                     "",
                     "Oh, and for those of you trying to be clever and making 'foo' contain {{bar}}, which contains {{baz}} "
                    ."which contains {{this}}, which contains {{that}} which contains ... etc, etc ... which contains "
                    ."{{foo}} - that won't work either. vars.pl will quite happily plough through as many levels of depth "
                    ."as you care to create, detect your loop, and ridicule you, making you the laughing stock of all of "
                    ."your imaginary internet friends.",
                     "",
                );
    return @help;
}
sub help_cpvar {
    my @help = (
                     "",
                     "Synopsis: /cpvar [-f] variable name",
                     "",
                     "This is a fun one. Essentially, what this command does, is copies the value of an existing variable, "
                    ."into another variable. Using /cpvar as-is, is intended to make a copy of the value of the provided "
                    ."variable name, and place it in a new variable, which you name in the second argument. If you wish to "
                    ."copy the contents of one variable into another variable which already exists, then you must provide "
                    ."the '-f' flag, i.e. /cpvar -f foo bar.",
                     "",
                     "Note that any inserted variables that are contained in the variable being copied will be copied "
                    ."over as well, without being inflated. This means that say, if you had a variable called 'foo', "
                    ."which was used in 'bar', then if you copy the contents of 'bar' to 'baz', then 'baz' will also "
                    ."depend on 'foo'.",
                     "",
                     "Similarly to /editvar, any pathetic attempts to create loops of any depth will be met with scorn.",
                     "",
                     "TODO: add -p flag (p for 'preserve') which will allow one to copy the inflated values of a "
                    ."contained variable, such that later editing contained variables does not alter the value "
                    ."of the copied variable.",
                     "",
                );
    return @help;
}
sub help_varlist {
    my @help = (
                     "",
                     "Synopsis: /varlist",
                     "",
                     "This command takes no arguments (yet) and prints a list of all the variables you have saved. Simple.",
                     "TODO: maybe allow an optional argument to print all variables that match a given pattern.",
                     "",
                );
    return @help;
}
sub help_undo {
    my @help = (
                     "",
                     "Synopsis: /undo",
                     "",
                     "This command does exactly what it says on the tin. It will revert the last action that you completed "
                    ."through vars.pl services. Undoing an action will create an item in the redo buffer (see /redo).",
                     "",
                     "TODO: consider allowing command to take an integer argument, which will specify the number of steps to undo.",
                     "",
                );
    return @help;
}
sub help_redo {
    my @help = (
                     "",
                     "Synopsis: /redo",
                     "",
                     "Another self explanatory command. This one lets you redo any actions that you may have "
                    ."undone using /undo. Redoing an action will create an item in the undo buffer.",
                     "",
                     "Note that whenever a new action is completed (i.e. not an action from the undo buffer), "
                    ."the redo buffer is compeltely cleared out.",
                     "",
                     "TODO: Same as with /undo, consider allowing an integer argument, to specify number of steps to redo.",
                     "",
                );
    return @help;
}
sub help_help {
    my @help = (
                    "",
                    "Synopsis: /help",
                    "",
                    "Well you obviously know how this works... Substitue 'help' (not /help) with a subject, e.g. 'mkvar'.",
                    "",
                );
    return @help;
}

Irssi::command_bind('mkvar', 'cmd_mkvar');
Irssi::command_bind('rmvar', 'cmd_rmvar');
Irssi::command_bind('editvar', 'cmd_editvar');
Irssi::command_bind('cpvar', 'cmd_cpvar');
Irssi::command_bind('varhelp', 'help');
Irssi::command_bind('varlist', 'cmd_varlist');
Irssi::command_bind('undo', 'cmd_undo');
Irssi::command_bind('redo', 'cmd_redo');
#Irssi::signal_add('send text', 'varreplace');
Irssi::signal_add('send command', 'varreplace');
Irssi::signal_add_first("complete word", 'tab_complete');
