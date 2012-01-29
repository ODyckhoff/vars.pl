use strict;
use warnings;

BEGIN {
    use Storable;
    use Cwd;

    our (%config, %foo, $loaded, $firsterr, $seconderr, $farg, $sarg, @varcmds);
    my $hashref;
    eval 'exec $PERLLOCATION/bin/perl -x $0 ${1+"$@"} ;' if 0;
    
    my $cwd = &Cwd::cwd();
    Irssi::settings_add_str('vars', 'vardata_path', '/home/pyro/');
    $config{'vardata_path'} = Irssi::settings_get_str('vardata_path');

    if(-e $config{'vardata_path'}.'.vardata') {
        (($hashref = retrieve($config{'vardata_path'}.'.vardata')) && (%foo = %{$hashref}));
        #backwards compatibility - replace spaces in variable names with _
        foreach my $key (sort keys %foo) {
            my $old = $key;
            if($key =~ s/\s/_/g) {
                Irssi::print("WARNING: Variable '$old' renamed to '$key', since spaces are no longer permitted in variable names.");
            }
        }
    }
}
our (%config, %foo, $loaded, $firsterr, $seconderr, $farg, $sarg, @varcmds);

@varcmds = ('mkvar', 'rmvar', 'varlist', 'varhelp');

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
        Irssi::print("Variable '$farg' succesfully saved with value '$sarg'");
        store(\%foo, $config{'vardata_path'}.'.vardata');
    }
    return;
}

sub cmd_rmvar {
    my ($data) = @_;
    if(delete $foo{$data} && store(\%foo, $config{'vardata_path'}.'.vardata')) {
        Irssi::print("variable '$data' has been successfully deleted");
    }
    else {
        Irssi::print("variable '$data' not found");
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
    }
        #Irssi::print("After loop: data = $data");
	return $data;
}

sub listvars {
    if(! %foo) {
        Irssi::print('No variables found');
        return;
    }
    Irssi::print('Listing all variables:');
    foreach my $key (sort keys %foo) {
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
Irssi::command_bind('varhelp', 'help');
Irssi::command_bind('varlist', 'listvars');
#Irssi::signal_add('send text', 'varreplace');
Irssi::signal_add('send command', 'varreplace');
