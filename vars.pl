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
Irssi::command_bind('lsvar', 'cmd_lsvar');
Irssi::command_bind('undo', 'cmd_undo');
Irssi::command_bind('redo', 'cmd_redo');
Irssi::signal_add('send command', 'signal_proc');
Irssi::signal_add_first('complete word', 'tab_complete');

### SCRIPT SETUP ###
our( %cfg, %vars, %err, @varcmds, @tabcmds, @undo, @redo );

# Script configuration and constants.
my $user = getpwuid( $< );

%vars = ( );

%cfg = (
    NAME => 'varspl',
    VPATH => '/home/' . $user . '/.irssi/',
    USER => $user,
);

# Error constants.
use constant {
    ENOVARS => 1,
    ENOIN   => 2,
    ENOSRV  => 3,
    ELOOP   => 4,
};

%err = (
    1 => { 
        fatal => 1,
        text  => "No variables in vars datastructure."
    },

    2 => {
        fatal => 1,
        text  => "Empty input."
    },

    3 => {
        fatal => 1,
        text  => "Not connected to server."
    },

    4 => { 
        fatal => 1,
        text  => "Loop detected in variable."
    },
);

@varcmds = ( 'mkvar', 'rmvar', 'lsvar', 'undo', 'redo', 'edvar', 'cpvar' );
@tabcmds = ( 'mkvar', 'rmvar', 'edvar', 'cpvar' );
our $tabrgx = join( '|', @tabcmds );


### STARTUP CONTROL ###
Irssi::settings_add_str( $cfg{NAME}, $cfg{NAME} . '_setup', 'true' );
my $startup = Irssi::settings_get_str( $cfg{NAME} . '_setup' );

if( ! $startup ) {
    # First time this script has been loaded.
    Irssi::settings_add_str( $cfg{NAME}, $cfg{NAME} . '_varfile', '.vardata' );
}

my $fname = Irssi::settings_get_str( $cfg{NAME} . '_varfile' );
my $file  = $cfg{VPATH} . $fname;
if( -e $file ) {
    %vars = %{ retrieve( $file ) };
}

### SIGNAL PROCESSING ###
sub signal_proc {
    my ( $data, $server, $witem ) = @_;

    err( ENOVARS ) and return if not defined %vars;
    err( ENOIN   ) and return if not defined $data;

    # Don't operate on this script's commands.
    if( $data =~ /^\/((\w+var)|(un|re)do)(.*)$/ ) {
        my @matches = grep( /$1/, @varcmds );
        return if @matches;
    }

    err( ENOSRV  ) and return if ( ! $server || ! $server->{ connected } );

    my ( $code, $out ) = replace( $data );

    if( $code ) {
        # Error somewhere.
        err( $code );
        Irssi::signal_stop();
    }
    else {
        Irssi::signal_continue( $out, $server, $witem );
    }

    return;
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

    my ($arg) = shift;

    if(!%vars) {
        err( ENOVARS ) && return;
    }

    Irssi::print( '', MSGLEVEL_CLIENTCRAP );
    if($arg) {
        Irssi::print( "\x02\x035"."Listing all variables matching '$arg':", MSGLEVEL_CLIENTCRAP );
    }
    else {
        Irssi::print( "\x02\x035"."Listing all variables:", MSGLEVEL_CLIENTCRAP );
    }

    Irssi::print( "\x038name\x03: 'value' - ('\x033Expanded content if available\x03')", MSGLEVEL_CLIENTCRAP );
    Irssi::print( '=' x 50, MSGLEVEL_CLIENTCRAP );
    Irssi::print( '', MSGLEVEL_CLIENTCRAP );

    foreach my $key ( sort { lc( $a ) cmp lc( $b ) } keys %vars ) {

        my $value = $vars{ $key };
        my $check = chk_loop( $value );
        
        if( $check->{'error'} ) {
            err( ELOOP ) && return;
        }
        else {
            Irssi::print( "\x038\x02$key\x03" . ': \'' . $vars{$key} . '\''
                            . ( $check->{'text'} ? 
                                  " - ('\x033\x02\x02" . $check->{'text'} . "\x03')"
                              :
                                  ''
                              ), MSGLEVEL_CLIENTCRAP
                         )
            if( $value =~ qr/$arg/ || $key =~ qr/$arg/ || $check->{'text'} =~ qr/$arg/ );
        }
    }
}

sub replace {

    my $in = shift;

    err( ENOIN   ) if not $in;
    err( ENOVARS ) if not %vars;

}

### UTILITY SUBS ###
sub cmd_undo {

}

sub cmd_redo {

}

sub chk_loop {
    my %rtnobj = ();

    $rtnobj{'text'} = "testing";

    return \%rtnobj;
}

sub err {

    my $code = shift;

    Irssi::print('[varspl] Error: ' . $code . ' - "' . $err{ $code }{ 'text' } . '"', MSGLEVEL_CLIENTCRAP );
    return $code if( $err{ $code }{ 'fatal' } );

}

### PLUGIN SUBS ###


### HELP SUBS ###
sub cmd_help {

}
