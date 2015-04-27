use strict;
use warnings;

use Irssi;
use Irssi::TextUI;

use File::Copy;
use File::Path;
use Storable;

### IRSSI INTERNALS SETUP ###
our $VERSION = '2.0-alpha';
our %IRSSI = (
    author      => 'Owen Rodger Dyckhoff',
    name        => 'vars.pl',
    description => 'A more powerful variables interface for Irssi.'
);

Irssi::command_bind('mkvar', 'cmd_mkvar');
Irssi::command_bind('rmvar', 'cmd_rmvar');
Irssi::command_bind('edvar', 'cmd_edvar');
Irssi::command_bind('cpvar', 'cmd_cpvar');
Irssi::command_bind('help', 'cmd_help');
Irssi::command_bind('varlist', 'cmd_lsvar');
Irssi::command_bind('undo', 'cmd_undo');
Irssi::command_bind('redo', 'cmd_redo');
Irssi::signal_add('send command', 'signal_proc');
Irssi::signal_add_first('complete word', 'tab_complete');

### SCRIPT SETUP ###
our( %cfg, %vars, @varcmds, @tabcmds, @undo, @redo );
use constant {
    NAME => 'varspl',
}

@varcmds = ( 'mkvar', 'rmvar', 'lsvar', 'undo', 'redo', 'edvar', 'cpvar' );
@tabcmds = ( 'mkvar', 'rmvar', 'edvar', 'cpvar' );
our $tabrgx = join( '|', @tabcmds );


### STARTUP CONTROL ###
$startup = Irssi::settings_get_str( NAME . '_setup' );

if( ! $startup ) {
    # First time this script has been loaded.
    Irssi::settings_add_str( NAME, NAME . '_setup', 'true' );
    
}

### SIGNAL PROCESSING ###
sub signal_proc {

}

sub tab_complete {

}

### INTERNAL SUBS ###
sub cmd_mkvar {

}

sub cmd_rmvar {

}

sub cmd_edvar {

}

sub cmd_cpvar {

}

sub cmd_lsvar {

}

### UTILITY SUBS ###
sub cmd_undo {

}

sub cmd_redo {

}

### HELP SUBS ###
sub cmd_help {

}
