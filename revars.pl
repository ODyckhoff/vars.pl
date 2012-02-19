# vars.pl - an irssi script to store and use variables within the Irssi IRC client.

use strict;
use warnings;

# Other required modules.
use Irssi;
use Irssi::TextUI;

use Storable;

use File::Copy;
use File::HomeDir;
use File::Path;
use File::Spec::Functions;

# Important script startup instructions.
## Initialise required globally accessible variables.
our (%config, %vars, %regexes, @varcmds, @tabcmds);

## Set globally accessible variables, where appropriate/possible.
$config{'vardata_path'} = catfile( get_irssi_dir(), '.vardata' );

%regexes = (
    'move'   => qr/make_compatible_vars|mvvar/,
    'change' => qr/cpvar|editvar/,
    'add'    => qr/mkvar|/,
    'remove' => qr//,
);

## Move things around (if necessary) for backwards compatibility with older versions of the script.
make_compatible_dirs();

## Load the '.vardata' file if it exists and place contents in variable hash.
load_vars();

### If '.vardata' is loaded successfully, run more backwards compatibility operations.
make_compatible_vars();

# INITIALISATION COMPLETE.

# Add Irssi command bindings.
Irssi::command_bind(  'mkvar', 'cmd_mkvar'  );
Irssi::command_bind(  'rmvar', 'cmd_rmvar'  );
Irssi::command_bind('editvar', 'cmd_editvar');
Irssi::command_bind(  'cpvar', 'cmd_cpvar'  );
Irssi::command_bind(  'mvvar', 'cmd_mvvar'  );
Irssi::command_bind(   'help', 'cmd_help'   );
Irssi::command_bind('varlist', 'cmd_varlist');
Irssi::command_bind(   'undo', 'cmd_undo'   );
Irssi::command_bind(   'redo', 'cmd_redo'   );

# Add Irssi signals.
Irssi::signal_add('send command', 'var_replace');
Irssi::signal_add_first('complete word', 'tab_complete');

# Script specific subroutines.

## Utility subroutines.
sub gen_rand_name {
    # Generates a random variable name in the event of name collisions.
    my $rand_name;
    
    do {
        my $string;
        my $length = 8;
        my @chars = ('a'..'z', 'A'..'Z', '0'..'9');
        foreach (1 .. $length) {
            $string .= $chars[rand @chars];
        }
        $rand_name = $string;
    }
    while var_exists($rand_name);
    
    return $rand_name;
}

sub get_caller {
    # Get the name of the subroutine calling the subroutine that called this...
    # Not sure how to say that any simpler.
    return ( caller(2) )[3];
}

sub make_compatible_dirs {
    # Move files around from locations where an older script would expect things to be.
    my $home   = home();
    my $path   = catfile($home, '.vardata'); # Path of .vardata on older versions of vars.pl.
    my $script = $0; # Get the name of script in case the user renamed it and force unloading is necessary.
       
    $script =~ s/\.pl$//;

    if( -e $path ) {
        # Configuration from oldest versions of vars.pl.
        move($path, $config{'vardata_path'})
            or Irssi::print($!, MSGLEVEL_CLIENTERROR);
        
        Irssi::Command('script unload ' . $script); # Force unload script due to error.
    }

    $path = catfile( get_irssi_dir(), 'scripts/varspl/.vardata' ); # Path of .vardata on middle-aged versions of vars.pl.

    if( -e $path ) {
        # Configuration from middle-aged versions of vars.pl.
        move($path, $config{'vardata_path'})
            or Irssi::print($!, MSGLEVEL_CLIENTERROR);
        
        Irssi::Command('script unload ' . $script); # Force unload script due to error.

        # If we made it here, there's some redundant folders that need cleaning up.
        File::Path::rmtree( catfile( get_irssi_dir(), 'scripts/varspl' ) )
            or Irssi::print($! . ' Please remove this directory manually.',
                   MSGLEVEL_CLIENTERROR);

        # No force unload needed here, as relevant files have been moved successfully.
    }
}

sub make_compatible_vars {
    my $warning;
    foreach my $key (sort keys %vars) {
        my $old = $key;
        if($key =~ s/\s/_/g) {
            # First, replace spaces in variable names with an underscore.
            $warning = "WARNING: Variable '$old' marked for renaming to '$key', since spaces are no longer permitted in variable names.";
        }
        
        if($key =~ s/^_+//) {
            # Secondly, remove underscores from the beginning of variable names
            if($warning) {
                $warning = "WARNING: Variable '$old' marked for renaming to '$key', since spaces are no longer permitted and underscores should not begin variable names.";
            }
            else {
                $warning = "WARNING: Variable '$old' marked for renaming to '$key', since underscores should not begin variable names.";
            }
        }
        
        Irssi::print($warning, MSGLEVEL_CLIENTCRAP);

        if(var_exists($key)) {
            # Uh-oh, we have a name collision. Lets generate a random variable name and let the user know about it
            my $rand_name = gen_rand_name();
            $warning = "WARNING: Automatic attempt to rename variable '$old' causes a name collision with '$new'.\n"
                     . "Variable being given random name '$rand_name' instead. Use '/mvvar' to rename it.";
            $key = $rand_name;
        }

        Irssi::print($warning, MSGLEVEL_CLIENTCRAP);

        if($key != $old) {
            edit_vars($key, $old);
            remove_var($old);
            save_vars();
        }
    }
}

## Undo/Redo operations.
sub gen_stack {

}

sub undo {

}

sub redo {

}

## File operations.
sub load_vars {
    my $hashref;
    if( $hashref = retrieve($config{'vardata_path'}) ) {
        %vars = %{$hashref};
    }
    else {
        Irssi::print('No .vardata file found. This is either because this is your first run, or because permissions are wrong.' . "\n"
                   . 'If this is your first run, don\'t worry, this file will be created for you.' . "\n"
                   . 'If you have created variables before, please make sure that .vardata exists in \'' . $config{'vardata_path'} 
                   . '\' and that the correct permissions are set, then use /varsreload to try again.',
            MSGLEVEL_CLIENTCRAP);
    }
}

sub save_vars {
    store(\%vars, $config{'vardata_path'});
}

## Variables hash operations.
sub access_vars {
    
}

sub edit_vars {
    my $caller = get_caller();
    if($caller =~ /make_compatible_vars|mvvar/) {
        my ($new, $old) = @_;
        if(add_var($new)) {
            remove_var($old);
        }
    }
}

### access_vars operations
sub var_exists {
 
}

sub expand {
    # This subroutine will take care of checking for infinite loops as well as expansion.
    # There's nothing stopping a user with a rogue script fiddling with vars.pl variables and/or files.
    
}

### edit_vars operations
sub add_var {

}

sub change_var {
    
}

sub remove_var {
    
}

# Irssi signal subroutines.
sub var_replace {

}

sub tab_complete {

}


# Irssi command subroutines.
sub cmd_mkvar {
    my ($data) = @_;
    my ($name, $value);

    my @args    = split(/\s/, $data);
    my $argsize = scalar(@args);

    if($argsize < 2) {
        Irssi::print('Syntax Error: ' . $argsize ? 'Single' : 'No' . ' Argument Given',
            MSGLEVEL_CLIENTCRAP);
        Irssi::print('Type "/help vars mkvar" for command usage',
            MSGLEVEL_CLIENTCRAP);
        return;
    }
    else {
        $name = shift(@args); # Get the first argument, or name of the variable.
        $value = join(' ', @args); # Everything else is the value, so put the string back together.
        
        # Check variable name is legal.
        if(var_exists($name)) {
            Irssi::print("Error: variable '$name' already exists. Use /editvar to overwrite",
                MSGLEVEL_CLIENTCRAP);
            return;
        }
        if($name =~ /(^_)|(\W)/) {
            Irssi::print('Error: only alphanumeric characters (A-Z, a-z, 0-9 and _) are permitted in variable names, and names cannot start with underscores.',
                MSGLEVEL_CLIENTCRAP);
            return;
        }

        # Check variable value is legal, and doesn't initiate any loops.
        # This is theoretically impossible since you can't reference variables which don't exist, but it's always good to be safe.
        if($value) {
            
    }
}

sub cmd_rmvar {

}

sub cmd_editvar {

}

sub cmd_cpvar {

}

sub cmd_mvvar {

}

sub cmd_varlist {

}

sub cmd_undo {

}

sub cmd_redo {

}

sub cmd_help {

}
