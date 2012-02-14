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
our (%config, %vars, @varcmds, @tabcmds);

## Set globally accessible variables, where appropriate/possible.
$config{'vardata_path'} = catfile( get_irssi_dir(), '.vardata' );

## Move things around (if necessary) for backwards compatibility with older versions of the script.
make_compatible();

## Load the '.vardata' file if it exists and place contents in variable hash.
### If '.vardata' is loaded successfully, run more backwards compatibility operations.
#### Replace spaces in variable names with an underscore.
#### Remove underscores from the start of variable names.
##### Alert user of any resulting name collisions.
###### Assign the problem variable to a randomly generated name, and notify the user of this name.

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
sub get_caller {
    # Get the name of the subroutine calling the subroutine that called this...
    # Not sure how to say that any simpler.
    return ( caller(2) )[3];
}

sub make_compatible {
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
            or Irssi::print($! . ' Please remove this directory manually.', MSGLEVEL_CLIENTERROR);

        # No force unload needed here, as relevant files have been moved successfully.
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

}

sub save_vars {

}

## Variables hash operations.
sub access_vars {

}

sub edit_vars {

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

sub help {

}
