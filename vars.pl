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

Irssi::command_bind( 'mkvar', 'cmd_mkvar' );
Irssi::command_bind( 'rmvar', 'cmd_rmvar' );
Irssi::command_bind( 'edvar', 'cmd_edvar' );
Irssi::command_bind( 'cpvar', 'cmd_cpvar' );
Irssi::command_bind( 'help' , 'cmd_help'  );
Irssi::command_bind( 'lsvar', 'cmd_lsvar' );
Irssi::command_bind( 'undo' , 'cmd_undo'  );
Irssi::command_bind( 'redo' , 'cmd_redo'  );

Irssi::signal_add( 'send command', 'signal_proc' );
Irssi::signal_add_first( 'complete word', 'tab_complete' );

### SCRIPT SETUP ###
our( %cfg, %vars, %err, @varcmds, @tabcmds, @undo, @redo );

our $plainvar  = qr/\{\{(\w+)\}\}/;
our $pluginvar = qr/\{([^{}|]*?)\{(.+?)\}\}/; # {, } and | are reserved for script functionality.
                                                   # \ is just plain not allowed.
# Script configuration and constants.
my $user = getpwuid( $< );

%vars = ( );

%cfg = (
    NAME  => 'varspl',
    VPATH => '/home/' . $user . '/.irssi/',
    USER  => $user,
);

# Error constants.
use constant {
    ENOACT  => 0,
    ENOVARS => 1,
    ENOIN   => 2,
    ENOSRV  => 3,
    ELOOP   => 4,
    ENOKEY  => 5,
};

%err = (
    0 => {
        fatal => 0,
        text  => "No errors or nothing to do."
    },

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

    5 => {
        fatal => 1,
        text  => "No such variable '%s'"
    }
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

    if ( $data !~ '/' && ( ! $server || ! $server->{ connected } ) ) {
        Irssi::signal_continue( $data, $server, $witem );
        err( ENOSRV ) and return;
    }

    my ( $code, $out ) = replace( $data );
    Irssi::print($out);

    if( ! $code ) {
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

    my ( $arg ) = shift;

    if( ! %vars ) {
        err( ENOVARS ) && return;
    }

    Irssi::print( '', MSGLEVEL_CLIENTCRAP );
    if( $arg ) {
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
        
        if( $check->{ 'error' } ) {
            err( ELOOP ) && return;
        }
        else {
            my $txt = $check->{ 'text' };

            Irssi::print( "\x038\x02$key\x03" . ': \'' . $vars{ $key } . '\''
                            . ( $check->{ 'text' } ? 
                                  " - ('\x033\x02\x02" . $check->{ 'text' } . "\x03')"
                              :
                                  ''
                              ), MSGLEVEL_CLIENTCRAP
                         )
            if( $value =~ qr/$arg/ 
               || $key =~ qr/$arg/
               || $txt =~ qr/$arg/
            );
        }
    }
}

### UTILITY SUBS ###
sub replace {

    my $in = shift;
    my $out = $in; # Just in case.

    err( ENOIN   ) if not $in;
    err( ENOVARS ) if not %vars;

    # First check there's even any point.
    if( $in !~ /(\\*)($plainvar|$pluginvar)/ ) {
        return ( 0, $out );
    }

    # Loop through any possible matches.
    while( $in =~ /(\\*?)($plainvar|$pluginvar)/g ) {
        my ( $flag, $prefix, $name );
        if( $4 ) {
            $flag = 'plugin';
            $prefix = $4;
            $name = $5;
        }
        else {
            $flag = 'plain';
            $prefix = '';
            $name = $3;
            Irssi::print($name);
        }

        my $slashes  = '';
           $slashes  = $1 if defined $1;
        my $varmatch = $2;

        # Check slashes for escapisms.
        my $count = 0;
           $count = length( $slashes );

        if( $count % 2 ) {
            # Odd number of slashes, so this one is escaped.
            next;
        }
        else {
            err( ENOKEY, $name ) && return ( ENOKEY, $out ) if ! $vars{ $name } && $flag eq 'plain';

            my $replaced = '';
            $replaced = extrapolate( $name, $prefix );
            
            $varmatch =~ s/([\\\[\]\(\)\{\}\.\^\$\*\+\?])/\\$1/g;
            $out =~ s/(?<!\\)$varmatch/$replaced/;
        }
    }

    # Clean up.
    $out =~ s/\\\{/{/g;
    $out =~ s/\\\}/}/g;

    return (0, $out); 
}

sub extrapolate {
    my ( $name, $prefix ) = @_;
    my $tmp = '';

    if( ! $prefix || ( $prefix && $vars{ $name } ) ) {
        $tmp = $vars{ $name };
        if( $tmp =~ /\{\{.+\}\}/ ) {
            my @arr = replace( $tmp );
            $tmp = $arr[1];
        }
    }

    if( $prefix ) {
        $tmp = $name if not $tmp;
        $tmp = pluginHandler( $tmp, $prefix );
    }

    return $tmp;
}

sub chk_loop {
    my %rtnobj = ();

    $rtnobj{ 'text' } = "testing";

    return \%rtnobj;
}

sub err {

    my $code = shift;
    my $text = $err{ $code }{ 'text' };
    
    while( $text =~ /(%[sd])/g ) {
        my $arg = shift;
        $text =~ s/$1/$arg/;
    }

    Irssi::print( '[varspl] Error: ' . $code . ' - "' . $text . '"', MSGLEVEL_CLIENTCRAP );

    Irssi::signal_stop() if( $err{ $code }{ 'fatal' } );
}

sub save_vars {
    my $file = $cfg{ VPATH } . Irssi::settings_get_str( $cfg{ NAME } . '_varfile' );
    store( \%vars, $file ) if -e $file;
}

sub cmd_undo {

}

sub cmd_redo {

}

### PLUGIN SUBS ###

sub pluginHandler {

    my ( $text, $prefix ) = @_;

    return scalar reverse $text;

}

### HELP SUBS ###
sub cmd_help {

}
