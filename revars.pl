# vars.pl - an irssi script to store and use variables within irssi

use strict;
use warnings;

# Other required modules.
use Irssi;
use Irssi::TextUI;

use Storable;

use File::Copy;
use File::HomeDir;
use File::Path;
use File::Spec;

# Important script startup instructions.
    # Set required variables.
    # Move things around (if necessary) for backwards compatibility with older versions of the script.
    # Load the '.vardata' file if it exists and place contents in variable hash.
        # If '.vardata' is loaded successfully, run more backwards compatibility operations.
            # Replace spaces in variable names with an underscore.
            # Remove underscores from the start of variable names.
                # Alert user of any resulting name collisions.
                    # Assign the problem variable to a randomly generated name, and notify the user of this name.

# Add Irssi command bindings.

# Add Irssi signals.

# Script specific subroutines.

# Irssi command subroutines.
