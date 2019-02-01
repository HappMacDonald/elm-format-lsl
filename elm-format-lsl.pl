#!/bin/perl

=pod
Todo:
OK, current problem I've got to figure out how to solve.

1: the tokenizer relies on identifying static string tokens.

2: How to match against those when comment, such as /*-*/? Cannot rely
on whitespace deliniation there.

3: Probably (conditionally) "token matches last characters in running token string".

Just gotta figure out how to that. :O
=cut



use strict;
use warnings;
use Data::Dumper;
use constant { TRUE => 1, FALSE => 0 };
use constant { VERSION => "0.0.1" };

# Define a list of stages, to be used like an ADT.
my $modeRunner = 0;
use constant
{ STAGE_PRE_STATE => $modeRunner++ #0
, STAGE_DEFAULT_ROOT => $modeRunner++ #1
, STAGE_STATE_ROOT => $modeRunner++ #2
, STAGE_POST_STATE => $modeRunner++ #3
, STAGE_EVENT => $modeRunner++ #4
, STAGE_USER_FUNCTION => $modeRunner++ #5
, STAGE_COMMENT_NONE => $modeRunner++ #6
, STAGE_COMMENT_TO_EOL => $modeRunner++ #7
, STAGE_COMMENT_TO_MARK => $modeRunner++ #8

# Constant representing a bitmask of all stages combined
, STAGE_MASK_ALL => 1<<$modeRunner - 1
};

use Getopt::Long;
Getopt::Long::Configure ("bundling");

my $getopt =
{ help => FALSE
, output => "" #blank means "unspecified", EG "overwrite input files".
, yes => FALSE
, validate => FALSE
, stdin => FALSE
, tabsize => 4
};

my $stageStack;
my $tokenAtoms =
{ '//' =>
  [ { valid => stageMask(STAGE_COMMENT_NONE)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_TO_EOL; }
    }
  ]
, '/*' =>
  [ { valid => stageMask(STAGE_COMMENT_NONE)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_TO_MARK; }
    }
  ]
, '*/' =>
  [ { valid => stageMask(STAGE_COMMENT_TO_MARK)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_NONE; }
    }
  ]
, "\n" =>
  [ { valid => stageMask(STAGE_COMMENT_TO_EOL)
    , action => sub { $stageStack->{'commented'} = STAGE_COMMENT_NONE; }
    }
  ]
}
;

GetOptions
( $getopt
, "help|h"
, "output:s"
, "yes"
, "validate"
, "stdin"
, "tabsize:4"
);

usage() if($getopt->{'help'});

# Build a list of @targets based on remaining @ARGV input,
# such that targets matching directories get macro-expanded
# as though they were instead a list of all .lsl files within
# that directory.
my @targets;
while(my $target = shift @ARGV)
{ $target = escapeshellarg($target);
  if(defined(-d $target) && -d $target)
  { $target .= "/*.lsl"
  }
#  print Dumper("glob $target = ", glob $target);
  push @targets, glob $target;
}

# No targets on command line illicits usage.
usage() if(!@targets);

# Now for every pre-processed target, we check to see if that's really
# a file, and then run the process subroutine on them one by one.
my $exitStatus = 0;
while(my $target = shift @targets)
{ if(!defined(-e $target) || !-e $target)
  { print "Input file doesn't exist: $target\n";
    $exitStatus = 1;
    next;
  }
  process($target);
}

# Accept a filename, and endeavor to reformat that.
# Output strategy has not yet been decided upon.
sub process
{ my $target = shift;
  my $input;

  # Open the file into filehandle $input
  my $openStatus = open($input, "<", $target);
  if(!$openStatus)
  { print "Could not read file $target: @!\n";
    $exitStatus = 1;
    return;
  }

  # Prepare a state machine tracker
  $stageStack =
  { base => STAGE_PRE_STATE
  , token => ''
  , commented => STAGE_COMMENT_NONE
  , quoted => FALSE
  };

  # iterate over every line of the file
  while(my $line = <$input>)
  { my @chars = split '', $line;

    # iterate over every character on every line
    while(my $char = shift(@chars))
    { # If current character is whitespace, then process all buffered
      # characters thus far as a token before re-running character loop.      
      if($char =~ /[ \t]/)
      { tokenProcess();
        next;
      }

      # Otherwise, add current character into buffer.
      $stageStack->{'token'} .= $char;
# print Dumper(tokenAtomsHash($stageStack));

      # If the current buffer matches a token valid in current state,
      # then process it as such
      tokenProcess() if(tokenAtomsHash($stageStack)->{$stageStack->{'token'}});

      # Otherwise, if current character is a newline, then clear the buffer.
      $stageStack->{'token'} = '' if($char=="\n");
    }
  }
  close($input);
}

# Try to process characters in our buffer as a token in the current state.
sub tokenProcess
{ # Take copy of buffer, but pre-emptively clear real buffer.
  my $token = $stageStack->{'token'};
  $stageStack->{'token'} = '';

  # Skip processing if buffer is empty
  return if(!$token);

  # Create a mask representing the current confluence of states
  my $mask = stageMask($stageStack);

  # If we have any scenes where this token may be valid, enumerate them.
  if(my $scenes = $tokenAtoms->{$token})
  { foreach my $scene (@$scenes)
    { # For each scene, test to see if that scene is valid in current state.
      if($scene->{'valid'} & $mask)
      { # If so, perform the action of that scene.
        $scene->{action}();
# print Dumper($stageStack) ."\n";
        # And clear the character buffer as a consequence.
        $stageStack->{'token'} = '';
        return;
      }
    }
  }
# print $stageStack->{'commented'} ."($token):";

  # Don't complain about unexplained tokens while processing a comment,
  # or a string literal.
  return
    if
    ( $stageStack->{'commented'} ne STAGE_COMMENT_NONE
    ||$stageStack->{'quoted'}
    );

  #Otherwise, we should only see tokens that we expect so complain.
  print
  ( "Found unexpected token: ($token) in mode/mask $mask\n"
  );
}


# This accepts a (potentially hypothetical) state machine,
# and returns a hash keyed by every token for which the current
# state may have valid scenes.
sub tokenAtomsHash
{ my $mask = stageMask(shift());
  my $tokenAtomsHash;
  foreach my $token (keys %$tokenAtoms)
  { foreach my $scene (@{$tokenAtoms->{$token}})
    { if($scene->{'valid'} & $mask)
      { $tokenAtomsHash->{$token}=1;
        last;
      }
    }
  }
  return $tokenAtomsHash;
}

# This accepts EITHER a hypothetical state OR an integer mode,
# and returns a bitmask of either that mode or of all modes
# within that state description or'ed together.
sub stageMask
{ my $maskInput = shift;
  if(ref($maskInput) eq "HASH")
  { my $a = stageMask($maskInput->{'base'});
    my $b = stageMask($maskInput->{'commented'});
    # die("($a | $b == ". ($a|$b) .")");
    return($a|$b);
  } 
  return 1<<$maskInput;
}

# This is used to ensure that user-specified file paths get interpreted
# correctly by our file matching algorithm.
sub escapeshellarg
{ my $arg = shift;

  $arg =~ s/'/'\\''/g;
  return "'" . $arg . "'";
}

# If user invoked this command incorrectly, or if they asked for it,
# then they are shown this page of help information and the program exits.
sub usage
{ printf "elm-format-lsl.pl %s\n\n", VERSION;
  print <<~EOF;
    Usage: perl elm-format-lsl.pl [INPUT] [--output FILE] [--yes] [--validate] [--stdin]
      Format LSL source files in ELM-like fashion

    Available options:
      -h,--help     Show this help text
      --output FILE Write output to FILE instead of overwriting the given
                    source file.
      --yes         Reply 'yes' to all automated prompts.
      --validate    Check if files are formatted without changing them.
      --stdin       Read from stdin, output to stdout.
      --tabsize     How many spaces to tab (Default = 4)

    Examples:
      elm-format-lsl.pl Main.lsl                     # formats Main.lsl
      elm-format-lsl.pl Main.lsl --output Main2.lsl  # formats Main.lsl as Main2.lsl
      elm-format-lsl.pl src/                         # format all *.lsl files in the src directory

    Full guide to using elm-format-lsl.pl .. doesnt' yet exist.
    Because I'm lazy.
    Deal. ( •_•)>⌐■-■  (⌐■_■)
    EOF
  exit 1;
}

