use strict;
use warnings;

use Irssi;
use Irssi::TextUI;

use Class::Inspector;
use Class::Unload;
use Module::Load;
use Module::Reload::Selective;

use List::Util qw(first);

use File::Copy;
use File::Path;
use Storable;

use Encode;
use Text::Unidecode;

### IRSSI INTERNALS SETUP ###
our $VERSION = '2.0.2';
our %IRSSI = (
    author      => 'Owen Rodger Dyckhoff',
    name        => 'vars.pl',
    description => 'A more powerful variables interface for Irssi.'
);

Irssi::command_bind( 'vars',  'cmd_vars'  );
Irssi::command_bind( 'help' , 'cmd_help'  );

Irssi::signal_add( 'send command', 'signal_proc' );
Irssi::signal_add_first( 'complete word', 'tab_complete' );

### SCRIPT SETUP ###
our( %cfg, %vars, %err, %plugins, @varcmds, @tabcmds, @undo, @redo );

our $plainvar  = qr/\{\{(\w+)\}\}/;
our $pluginvar = qr/\{([^{}|]*?)\{(.+?)\}\}/; # {, } and | are reserved for script functionality.
                                              # \ is just plain not allowed.
# Script configuration and constants.
my $user = getpwuid( $< );

%vars = ( );

%cfg = (
    NAME  => 'varspl',
    VPATH => '/home/' . $user . '/.irssi/scripts/.varspl/',
    USER  => $user,
    SELF  => 'Irssi::Script::vars'
);

mkdir $cfg{ VPATH } unless -e $cfg{ VPATH };

push @INC, $cfg{ VPATH };

# Error constants.
use constant {
    ENOACT    => 0,
    ENOVARS   => 1,
    ENOBUF    => 2,
    ENOSRV    => 3,
    ELOOP     => 4,
    ENOKEY    => 5,
    ENOPREFIX => 6,
    ENOPLUG   => 7,
    EBADPLUG  => 8,
    EEXISTS   => 9,
};

%err = (
    0 => { # ENOACT
        fatal => 0,
        text  => "No errors or nothing to do."
    },
    1 => { # ENOVARS
        fatal => 1,
        text  => "No variables in vars datastructure."
    },
    2 => { # ENOBUF
        fatal => 1,
        text  => "Empty input."
    },
    3 => { # ENOSRV
        fatal => 1,
        text  => "Not connected to server."
    },
    4 => { # ELOOP
        fatal => 1,
        text  => "Loop detected in variable."
    },
    5 => { # ENOKEY
        fatal => 1,
        text  => "No such variable '%s'"
    },
    6 => { # ENOPREFIX
        fatal => 1,
        text  => "No plugin exists with prefix: %s"
    },
    7 => { # ENOPLUG
        fatal => 1,
        text  => "No such plugin %s"
    },
    8 => { # EBADPLUG
        fatal => 1,
        text  => "Error in plugin. %s"
    },
    9 => { #EEXISTS
        fatal => 1,
        text  => "Variable '%s' already exists."
    },
);

%plugins = (
    'loaded' => [],
);

@varcmds = ( 'script', 'vars' );

### STARTUP CONTROL ###
Irssi::settings_add_str( $cfg{NAME}, $cfg{NAME} . '_setup', 'false' );

Irssi::settings_add_str( $cfg{NAME}, $cfg{NAME} . '_varfile', '.vardata' );
Irssi::settings_add_str( $cfg{NAME}, $cfg{NAME} . '_autoplugins', '' );

my $fname = Irssi::settings_get_str( $cfg{NAME} . '_varfile' );
my $file  = $cfg{VPATH} . $fname;
if( -e $file ) {
    %vars = %{ retrieve( $file ) };
}

my @autoplugins = split( /[, ]{1,2}/, Irssi::settings_get_str( $cfg{NAME} . '_autoplugins' ) );
foreach my $auto ( @autoplugins ) {
    load_plugin( $auto ) if $auto;
}

### SIGNAL PROCESSING ###
sub signal_proc {
    my ( $data, $server, $witem ) = @_;

    err( ENOVARS ) and return if not %vars;
                       return if not $data;

    # Don't operate on this script's commands.
    if( $data =~ /^\/(vars|script)(.*)$/ ) {
        my @matches = grep( /$1/, @varcmds );
        return if @matches;
    }

    # Don't operate on commands that start with /^
    return if $data =~ /^\/\^/;

    if ( $data !~ '/' && ( ! $server || ! $server->{ connected } ) ) {
        Irssi::signal_continue( $data, $server, $witem );
        err( ENOSRV );
        return;
    }

    my ( $code, $out ) = replace( $data );

    if( ! $code && $out ) {
        Irssi::signal_continue( $out, $server, $witem );
    }

    return;
}

sub tab_complete {
    my ( $strings, $window, $arg, $linestart, $want_space ) = @_;
    #Irssi::print( "$linestart, $arg" );
    if( $linestart =~ /^\/vars$/i ) {
        # Completing sub-commands.
        @$strings = grep( /^$arg/,
            [ 'mk', 'rm', 'ed', 'cp', 'ls', 'mv', 'load', 'unload', 'autoload' ]
        );
        $$want_space = 1;

        Irssi::signal_stop;
    }
    elsif( $linestart =~ /^\/vars autoload$/i ) {
        @$strings = grep( /^$arg/, [ 'add', 'rm' ] );
        $$want_space = 1;
        Irssi::signal_stop;
    }
    elsif( $linestart =~ /^\/vars autoload (rm|remove)$/i ) {
        @$strings = grep( /^$arg/, split( /\s/, Irssi::settings_get_str( $cfg{ NAME } . '_autoplugins' ) ) );
        $$want_space = 0;
        Irssi::signal_stop;
    }
    elsif( $linestart =~ /^\/vars autoload add$/i || $linestart =~ /^\/vars load$/i ) {
        opendir( my $dh, $cfg{ VPATH } . '/Plugins/' );
        foreach( grep { /^[^\.]/ && -f $cfg{ VPATH } . '/Plugins/' . $_ } readdir( $dh ) ) {
            s/\.pm$//;
            push @$strings, $_ if /^$arg/;
        }
        $$want_space = 0;
        Irssi::signal_stop;
    }
    elsif( $linestart =~ /^\/vars unload$/i ) {
	@$strings = grep( /^$arg/, @{ $plugins{ loaded } } );
        $$want_space = 0;
        Irssi::signal_stop;
    }
    else {
        return;
    }
}

### INTERNAL SUBS ###
sub cmd_vars {

    my @args = split( /\s/, $_[0] );
    my $cmd = shift @args;

    # Parse command.
    # Plugin commands.
    if( $cmd =~ /^load/i ) {
        load_plugin( $args[0] );
    }
    if( $cmd =~ /unload/i ) {
        unload_plugin( $args[0] );
    }
    if( $cmd =~ /autoload/i ) {
        if( $args[0] =~ /^add$/i ) {
            autoload_add( $args[1] );
        }
        elsif( $args[0] =~ /^(rm|remove)$/i ) {
            autoload_rm( $args[1] );
        }
    }

    # Script commands.
    if( $cmd =~ /^mk$/i ) {
        cmd_mkvar( @args );
    }
    if( $cmd =~ /^rm$/i ) {
        cmd_rmvar( @args );
    }
    if( $cmd =~ /^ed$/i ) {
        cmd_edvar( @args );
    }
    if( $cmd =~ /^cp$/i ) {
        cmd_cpvar( @args );
    }
    if( $cmd =~ /^ls$/i ) {
        cmd_lsvar( @args );
    }
    if( $cmd =~ /^mv$/i ) {
        cmd_mvvar( @args );
    }
}

sub cmd_mkvar {
    my $name  = shift;
    my $value = join( " ", @_ );

    if( defined $vars{ $name } ) {
        err( EEXISTS, $name );
        return;
    }
    
    if( chk_loop( $value, $name ) ) {
        $vars{ $name } = $value;
        &save_vars;
    }
}

sub cmd_rmvar {
    my $name = shift;

    if( defined $vars{ $name } ) {
        delete $vars{ $name };
        &save_vars;
    }
    else {
        err( ENOKEY, $name );
    }
}

sub cmd_edvar {
    my $name  = shift;
    my $value = join( " ", @_ );

    if( ! defined $vars{ $name } ) {
        err( ENOKEY, $name );
        return;
    }
    
    if( chk_loop( $value, $name ) ) {
        $vars{ $name } = $value;
        &save_vars;
    }
}

sub cmd_cpvar {

    my $force = 0;
    my $full  = 0;
    my $tot   = scalar( @_ ) - 1;
    my @data  = ();

    for( my $count = 0; $count < $tot; $count++ ) {
        if( $_[ $count ] =~ /^(-f|--force|-x)$/i ) {
            my $flag = $1;
            $force = 1 if( $flag =~ /-f/ );
            $full  = 1 if( $flag =~ /-x/ );

            if( $count == 0 ) {
                # Everything but the first element.
                shift;
                @data = @_;
            }
            elsif( $count == $tot ) {
                # Everything but the last element.
                pop;
                @data = @_;
            }
            else {
                @data = ( 
                    @_[   0..( $count - 1 )  ], 
                    @_[ ( $count + 1 )..$tot ]
                );
            }
        }
    }

    my $cur = shift;
    my $new = shift;

    if( ! defined $vars{ $cur } ) {
        err( ENOKEY, $cur );
        return;
    }

    if( defined $vars{ $new } && ! $force ) {
        err( EEXISTS, $new );
        return;
    }

    if( $vars{ $cur } && chk_loop( $vars{ $cur }, $new ) ) {
        if( $full ) {
            $vars{ $new } = replace( $vars{ $cur } );
        }
        else {
            $vars{ $new } = $vars{ $cur };
        }
        &save_vars;
    }
}

sub cmd_mvvar {

    my $force = 0;
    my @data = ();
    my $tot = scalar( @_ );

    if( $tot == 3 && $_[0] =~ /-f|--force/ ) {
        $force = 1;
        shift;
    }

    my $cur = shift;
    my $new = shift;

    if( ! defined $vars{ $cur } ) {
        err( ENOKEY, $cur );
        return;
    }

    if( defined $vars{ $new } && ! $force ) {
        err( EEXISTS, $new );
        return;
    }

    if( $vars{ $cur } && chk_loop( $vars{ $cur }, $new ) ) {
        $vars{ $new } = $vars{ $cur };
        delete $vars{ $cur };
        &save_vars;
    }
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
        my $full = replace( $value );
    
        Irssi::print( "\x038\x02$key\x03" . ': \'' . $vars{ $key } . '\''
                        . ( $full ne $value ? 
                              " - ('\x033\x02\x02" . $full . "\x03')"
                          :
                              ''
                          ), MSGLEVEL_CLIENTCRAP
                     )
        if( ! $arg 
         || ( $arg 
              &&
                ( $value =~ qr/$arg/ 
               || $key   =~ qr/$arg/
               || $full  =~ qr/$arg/
                )
            )
        );
    }
}

### UTILITY SUBS ###
sub replace {

    my $in = shift;
    #my $out = encode('utf8', $in);
    my $out = $in; # Just in case.


    err( ENOBUF  ) if not $in;
    err( ENOVARS ) if not %vars;

    # First check there's even any point.
    if( $in !~ /(\\*)($plainvar|$pluginvar)/ ) {
        return ( 0, $out );
    }

    # Loop through any possible matches.
    while( $out =~ /(\\*?)($plainvar|$pluginvar)/g ) {
        my ( $flag, $prefix, $name );
        #Irssi::print("Matched: $&");
        if( $4 ) {
            $flag = 'plugin';
            $prefix = $4;
            $name = $5;
        }
        else {
            $flag = 'plain';
            $prefix = '';
            $name = $3;
        }

        my $slashes  = '';
           $slashes  = $1 if defined $1;
        my $varmatch = $2;

        #Irssi::print("out = $out, varmatch = $varmatch");

        # Check slashes for escapisms.
        my $count = 0;
           $count = length( $slashes );

        if( $count % 2 ) {
            # Odd number of slashes, so this one is escaped.
            next;
        }
        else {
            err( ENOKEY, $name ) && return ( ENOKEY, $out ) if ! $vars{ $name } && $flag eq 'plain';

            my $replaced = extrapolate( $name, $prefix );
            #$replaced =~ s/([^[:ascii:]]+)/unidecode($1)/ge;
            #Irssi::print("replaced = $replaced ( $prefix -> $name )");

            return if ! $replaced;
            
            #$varmatch =~ s/([\\\[\]\(\)\{\}\.\^\$\*\+\?\/])/\\$1/g;
            #Irssi::print("out (before substitution) = $out");
            my $re = qr/(?<!\\)$varmatch/;
            #Irssi::print("Compiled regex: $re");
            $out =~ s/$re/$replaced/;
            #Irssi::print("out = $out, varmatch = $varmatch");

#            for my $c ( split //, $out ) {
#                Irssi::print("Character: $c, Code: " . ord($c));
#            }

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
    my ( $varvalue, $vartocheck ) = @_;

    my $tmp = $varvalue;

    while( $tmp =~ /$pluginvar/ ) {
        my $newname = $2;

        if( $newname eq $vartocheck ) {
            err( ELOOP );
            return 0;
        }
        if( defined $vars{ $newname } ) {
            $tmp =~ s/$pluginvar/$vars{ $newname }/;
        }
        else {
            $tmp =~ s/$pluginvar/$newname/;
        }
    }

    return 1;
}

sub err {

    my $code = shift;
    my $text = $err{ $code }{ 'text' };
    
    while( $text =~ /(%[sd])/g ) {
        my $arg = shift;
        $text =~ s/$1/$arg/;
    }

    Irssi::print( '[varspl] Error: ' . $code . ' - "' . $text . '"', MSGLEVEL_CLIENTCRAP );

    Irssi::signal_stop() if( $err{ $code }{ 'fatal' } && $code != ENOSRV );
}

sub save_vars {
    my $file = $cfg{ VPATH } . Irssi::settings_get_str( $cfg{ NAME } . '_varfile' );
    store( \%vars, $file ) if -e $file;
}

### PLUGIN SUBS ###

sub pluginHandler {

    my ( $text, $prefix ) = @_;
    my $out;

    foreach my $plugin ( sort keys %plugins ) {
        next if $plugin eq 'loaded';

        if( $plugins{ $plugin }{ prefix } eq $prefix ) {
            $out = $plugins{ $plugin }{ class }->do_convert( $text );
            #Irssi::print($out);
        }
    }

    if( ! $out ) {
        err( ENOPREFIX, $prefix ) && return;
    }
    return $out;
}

sub load_plugin {
    my ( $name ) = @_;

    my $pluginclass = "Plugins::$name";
    my $requirement = $cfg{ VPATH } . "Plugins/$name.pm";

    if( ! valid_plugin( $requirement ) ) {
        return;
    }

    if( Class::Inspector->loaded( $pluginclass ) ) {
        foreach my $key ( sort keys %INC ) {
            delete $INC{ $key } if ( $key =~ /Plugins\/$name/ );
        }
        Class::Unload->unload( $pluginclass );
        #&Module::Reload::Selective::reload( $pluginclass );
    }
    
    load $requirement;

    my $plugin = new $pluginclass;

    # Register plugin.
    $plugins{ $name } = {
        class   => $plugin,
        plugpkg => $plugin->{ classpack },
        version => $plugin->{ version },
        info    => $plugin->{ info },
        prefix  => $plugin->{ prefix },
    };

    push @{ $plugins{ loaded } }, $name;
    Irssi::print( "Loaded plugin: $name" );
}

sub unload_plugin {

    my ( $name ) = @_;

    my $class = 'Plugins::' . $name;

    foreach my $key ( sort keys %INC ) {
        delete $INC{ $key } if $key =~ /Plugins\/$name/;
    }
    Class::Unload->unload( $class );

    return if not $plugins{ $name };
    delete $plugins{ $name };

    my $index = first { $plugins{ 'loaded' }[$_] eq $name } 0..scalar( $plugins{ 'loaded' } );
    delete $plugins{ 'loaded' }[ $index ];

    Irssi::print( "Unloaded plugin: $name" );
}

sub valid_plugin {
    my ( $plugin ) = @_;

    if( ! -e $plugin ) {
        # It doesn't exist. Invalid.
        err( ENOPLUG, $plugin );
        return 0;
    }

    if( ( my $res = `perl -c $plugin 2>&1` ) !~ /syntax OK/ ) {
        # The code is bad and the developer should feel bad. Invalid.
        err( EBADPLUG, $plugin );
        return 0;
    }

    # Check for subroutines and required variables.
    my ( $ver, $inf, $con, $strict, $warn, $sub_do, $prefix, $export );
    open( my $fh, $plugin ) or die "Couldn't open file: $!";

    while( <$fh> ) {
        $strict = ( /(?<!#)\s*use strict/     ) ? 1 : 0;
        $warn   = ( /(?<!#)\s*use warnings/   ) ? 1 : 0;
        $sub_do = ( /(?<!#)\s*sub do_convert/ ) ? 1 : 0;
        $prefix = ( /(?<!#)\s*our \$PREFIX = '(.)';/ ) ? 1 : 0;
        $export = ( /(?<!#)\s*our \@EXPORT_OK = qw\( do_convert new \)/ ) ? 0 : 0;

        if( $prefix == 1 ) {
            foreach my $plgname ( sort keys %plugins ) {
                next if $plgname eq 'loaded';
                if( $plugins{ $plgname }{ prefix } eq $1 ) {
                    $prefix = 0;
                }
                else {
                    $prefix = -1; # Indicate that it's been checked to avoid looping every time.
                }
            }
        }
    }
    close $fh;
    if( grep( 0, [ $strict, $warn, $sub_do, $prefix, $export ] ) ) {
        err( EBADPLUG, $plugin );
        return 0;
    }
    # Passed all checks.
    return 1;
}

sub autoload_add {
    my ( $plugin ) = @_;

    my $list  = Irssi::settings_get_str( $cfg{ NAME } . '_autoplugins' );
       $list .= $plugin . " ";

    Irssi::settings_set_str( $cfg{ NAME } . '_autoplugins', $list );
}

sub autoload_rm {
    my ( $plugin ) = @_;

    my $list = Irssi::settings_get_str( $cfg{ NAME } . '_autoplugins' );
       $list =~ s/$plugin\s//;

    Irssi::settings_set_str( $cfg{ NAME } . '_autoplugins', $list );
}

### HELP SUBS ###
sub cmd_help {

}
